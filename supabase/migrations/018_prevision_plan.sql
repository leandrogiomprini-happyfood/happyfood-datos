-- 018_prevision_plan.sql
-- Prevision de consumo de insumos con el plan de produccion semanal (traspaso §4: "pasado real,
-- futuro planificado"; cobertura descontando el stock DIA POR DIA, no dividiendo por un promedio).
--
-- Metodo (pensado para que los errores de receta se cancelen):
--   1. Cuanto insumo lleva cada bulto, en teoria: recetas (kg por masa y kg por unidad) + envases por
--      bulto (traspaso §6).
--   2. Consumo teorico de las ultimas 8 semanas segun el parte de produccion, y consumo teorico de cada
--      dia del plan. Mismo calculo para los dos.
--   3. Consumo previsto de un dia del plan = consumo MEDIDO por dia x (teorico del plan ese dia /
--      teorico promedio diario de las ultimas 8 semanas). Asi la merma, los rindes y las recetas
--      incompletas afectan igual al pasado y al futuro y se cancelan; lo que cambia es el mix y el
--      volumen que dice el plan.
--   4. Despues del ultimo dia cargado en el plan se vuelve al consumo medido. Los insumos que no
--      aparecen en recetas ni envases usan siempre el consumo medido.
-- Se puede volver a ejecutar sin riesgo.

-- 1. Que receta usa cada producto (por los digitos 2 y 3 del codigo: 3001 -> "00" -> DDL).
--    El mixto (303x) es un tercio de DDL, Chocolate y Mani.
create table if not exists core.producto_receta (
  prefijo          text not null,
  producto_receta  text not null,
  peso             numeric not null default 1,
  primary key (prefijo, producto_receta)
);
alter table core.producto_receta enable row level security;
revoke all on core.producto_receta from anon, authenticated;

insert into core.producto_receta (prefijo, producto_receta, peso) values
  ('00', 'DDL', 1), ('01', 'CHOCOLATE', 1), ('02', 'MANI', 1),
  ('03', 'DDL', 0.3333), ('03', 'CHOCOLATE', 0.3333), ('03', 'MANI', 0.3334),
  ('04', 'DDL S/A', 1), ('05', 'BOCADITO', 1), ('07', 'G NAR sem', 1), ('08', 'Galletas coco', 1),
  ('09', 'Galletas Pera', 1), ('10', 'Alf coco', 1), ('11', 'Galleta Limon', 1),
  ('12', 'Talitas clasicas', 1), ('13', 'Talitas Jamon', 1), ('14', 'Talitas Queso', 1),
  ('15', 'Marinera', 1), ('16', 'Talita Andina', 1), ('17', 'Marinera Andina', 1),
  ('9001', 'Alfajor Soja', 1)
on conflict (prefijo, producto_receta) do update set peso = excluded.peso;

-- Kg de producto por masa (rinde oficial x gramaje, diseño §16). Solo pesa la proporcion entre
-- productos que comparten un insumo; el metodo del paso 3 cancela el valor absoluto.
create table if not exists core.recetas_rinde (
  producto_receta      text primary key,
  kg_producto_por_masa numeric not null check (kg_producto_por_masa > 0)
);
alter table core.recetas_rinde enable row level security;
revoke all on core.recetas_rinde from anon, authenticated;

insert into core.recetas_rinde values
  ('DDL', 117.5), ('CHOCOLATE', 117.5), ('MANI', 117.5), ('DDL S/A', 117.5), ('Alf coco', 117.5),
  ('Alfajor Soja', 105.75), ('BOCADITO', 188), ('G NAR sem', 48.2), ('Galletas coco', 48.2),
  ('Galletas Pera', 48.2), ('Galleta Limon', 48.2), ('Talitas clasicas', 48), ('Talita Andina', 43.2),
  ('Talitas Jamon', 40.8), ('Talitas Queso', 40.8), ('Marinera', 40.8), ('Marinera Andina', 40.8)
on conflict (producto_receta) do update set kg_producto_por_masa = excluded.kg_producto_por_masa;

-- 2. Insumo teorico por bulto de cada producto.
create or replace view calc.insumo_por_bulto as
with prod as (
  select p.codigo::int as producto_codigo, p.unidades_por, p.kg_por, pr.producto_receta, pr.peso
  from core.productos p
  join core.producto_receta pr
    on pr.prefijo = case when p.codigo = '9001' then p.codigo else substring(p.codigo, 2, 2) end
  where p.nivel = 'bulto' and p.kg_por > 0
), ingredientes as (
  select prod.producto_codigo, r.insumo_codigo,
         sum(prod.peso * case when r.base = 'kg_por_masa' then prod.kg_por * r.kg / rr.kg_producto_por_masa
                              else prod.unidades_por * r.kg end) as cantidad
  from prod
  join core.recetas r on r.producto_receta = prod.producto_receta
  left join core.recetas_rinde rr on rr.producto_receta = prod.producto_receta
  where r.base = 'kg_por_unidad' or rr.kg_producto_por_masa > 0
  group by 1, 2
), empaque as (
  select e.producto_codigo, x.insumo_codigo, x.cantidad
  from core.envases_producto e
  cross join lateral (values
    (e.bandeja, case when e.producto_codigo in (3001, 3011, 3021, 3041, 3051, 3101) then 30
                     when e.producto_codigo in (3073, 3083, 3093, 3113, 3153, 3173) then 20
                     when e.producto_codigo in (3121, 3131, 3141, 3161) then 24 end),
    (e.display, case when e.producto_codigo in (3070, 3080, 3090, 3110) then 12 end),
    (e.flexible_1, case when e.producto_codigo in (3001, 3011, 3021, 3041, 3051, 3101) then 90
                        when e.producto_codigo in (3070, 3080, 3090, 3110) then 144
                        when e.producto_codigo in (3073, 3083, 3093, 3113, 3153, 3173) then 20
                        when e.producto_codigo in (3121, 3131, 3141, 3161) then 24 end),
    (e.flexible_2, case when e.producto_codigo in (3001, 3011, 3021, 3041, 3051, 3101) then 30 end)
  ) as x(insumo_codigo, cantidad)
  where x.insumo_codigo is not null and x.cantidad is not null
)
select producto_codigo, insumo_codigo, sum(cantidad) as cantidad
from (select * from ingredientes union all select * from empaque) t
group by 1, 2;

-- 3. Teorico de las ultimas 8 semanas segun el parte. Las bandejas de semielaborado (2xx1) se pasan
--    a bultos de su producto (3xx1, 30 bandejas); los armados y rearmados no consumen receta.
create or replace view calc.teorico_real as
with b as (
  select fecha,
         case when unidad_cantidad = 'bandejas'
              then ('3' || substring(lpad(producto_codigo::text, 4, '0'), 2, 3))::int
              else producto_codigo end as producto_codigo,
         case when unidad_cantidad = 'bandejas' then cantidad / 30.0 else cantidad end as bultos
  from core.produccion_partes
  where unidad_cantidad <> 'armado'
    and coalesce(tipo, '') not in ('Rearmado', 'Retrabajo')
    and fecha > current_date - 56 and fecha <= current_date
    and cantidad > 0
)
select b.fecha, ipb.insumo_codigo, sum(b.bultos * ipb.cantidad) as cantidad
from b join calc.insumo_por_bulto ipb on ipb.producto_codigo = b.producto_codigo
group by 1, 2;

create or replace view calc.teorico_plan as
select pl.fecha, ipb.insumo_codigo, sum(pl.bultos * ipb.cantidad) as cantidad
from core.plan_produccion pl
join calc.insumo_por_bulto ipb on ipb.producto_codigo = pl.producto_codigo
where pl.fecha >= current_date and pl.bultos > 0
group by 1, 2;

-- 4. Stock dia por dia con el plan (180 dias).
create or replace view calc.prevision_dia as
with fin as (
  select max(fecha) as plan_hasta from core.plan_produccion where fecha >= current_date
), hist as (
  select insumo_codigo, sum(cantidad) / 56.0 as teorico_dia from calc.teorico_real group by 1
), d as (
  select s.insumo_codigo, s.stock_hoy, s.consumo_diario, h.teorico_dia, fin.plan_hasta,
         g::date as dia
  from calc.stock_insumos s
  cross join fin
  left join hist h on h.insumo_codigo = s.insumo_codigo
  cross join generate_series(current_date, current_date + 180, interval '1 day') g
)
select d.insumo_codigo, d.dia,
       case when d.plan_hasta is not null and d.dia <= d.plan_hasta and d.teorico_dia > 0
            then coalesce(d.consumo_diario, 0) * coalesce(tp.cantidad, 0) / d.teorico_dia
            else coalesce(d.consumo_diario, 0) end as consumo,
       d.dia <= d.plan_hasta and d.teorico_dia > 0 as segun_plan,
       d.stock_hoy
from d
left join calc.teorico_plan tp on tp.insumo_codigo = d.insumo_codigo and tp.fecha = d.dia;

create or replace view calc.prevision_insumos as
with acum as (
  select insumo_codigo, dia, consumo, segun_plan, stock_hoy,
         sum(consumo) over (partition by insumo_codigo order by dia) as acumulado
  from calc.prevision_dia
)
select insumo_codigo,
       min(dia) filter (where acumulado >= stock_hoy and consumo > 0) as fecha_quiebre_plan,
       bool_or(segun_plan) as usa_plan,
       round(sum(consumo) filter (where segun_plan), 3) as consumo_plan,
       max(dia) filter (where segun_plan) as plan_hasta
from acum
group by insumo_codigo;

-- 5. Stock con prevision (columnas nuevas al final).
create or replace view calc.stock_insumos_plan as
select s.*,
       p.usa_plan,
       p.plan_hasta,
       p.consumo_plan,
       p.fecha_quiebre_plan,
       case when s.modo = 'por_pedido' or s.estado = 'sin consumo' then null
            when p.fecha_quiebre_plan is null then 181
            else p.fecha_quiebre_plan - current_date end as dias_cobertura_plan,
       case
         when s.modo = 'por_pedido' then 'por pedido'
         when s.stock_hoy <= 0 then 'sin stock'
         when s.estado = 'sin consumo' then 'sin consumo'
         when coalesce(p.fecha_quiebre_plan - current_date, 181) < s.lead_time then 'crítico'
         when coalesce(p.fecha_quiebre_plan - current_date, 181) < s.lead_time + 14 then 'atención'
         else 'ok'
       end as estado_plan
from calc.stock_insumos s
left join calc.prevision_insumos p on p.insumo_codigo = s.insumo_codigo;

create or replace view public.reporte_stock_insumos as select * from calc.stock_insumos_plan;
revoke all on public.reporte_stock_insumos from anon, authenticated, public;
grant select on public.reporte_stock_insumos to looker_lectura;

-- 6. Control: estados con y sin plan, y los que mas cambian.
select 'estado con plan: ' || estado_plan as que, count(*)::text as valor
from calc.stock_insumos_plan group by estado_plan
union all select 'plan cargado hasta', max(plan_hasta)::text from calc.stock_insumos_plan
union all select 'productos con receta o envase', count(distinct producto_codigo)::text from calc.insumo_por_bulto
union all
select * from (
  select 'cambia: ' || insumo || ' (' || insumo_codigo || ')',
         coalesce(dias_cobertura::text, '-') || ' d sin plan -> ' || coalesce(dias_cobertura_plan::text, '-') || ' d con plan'
  from calc.stock_insumos_plan
  where usa_plan and dias_cobertura is not null and dias_cobertura_plan is not null
  order by abs(dias_cobertura - dias_cobertura_plan) desc
  limit 12
) x;
