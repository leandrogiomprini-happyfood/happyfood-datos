-- 026_reemplazo_bandeja_16.sql
-- Cuci (29/10/2026): la bandeja 16 (galleta familiar) se deja de usar; galletas familiares y marineras
-- pasan a la bandeja 17 (familiar reforzada 650 mic).
--   1. 16 pasa a inactivo (no se muestra).
--   2. Tabla de reemplazos: donde el mapa de envases (hoja KG del reporte de pedidos pendientes) diga 16,
--      se calcula con 17. Conviene igual corregir la hoja KG.
--   3. El consumo medido de la 16 en las ultimas 8 semanas se suma al de la 17 para la prevision: si no,
--      la 17 pareceria consumir menos de lo que va a consumir desde ahora. Cuando pasen 8 semanas el
--      reemplazo se puede borrar (delete from core.insumos_reemplazo where insumo_viejo = 16).
-- Se puede volver a ejecutar sin riesgo.

insert into core.insumos_config (insumo_codigo, modo, motivo) values
  (16, 'inactivo', 'Bandeja galleta familiar: reemplazada por la 17 (Cuci, 29/10/2026)')
on conflict (insumo_codigo) do update set modo = excluded.modo, motivo = excluded.motivo, actualizado = now();

create table if not exists core.insumos_reemplazo (
  insumo_viejo  int primary key,
  insumo_nuevo  int not null,
  desde         date not null default current_date,
  motivo        text
);
alter table core.insumos_reemplazo enable row level security;
revoke all on core.insumos_reemplazo from anon, authenticated;

insert into core.insumos_reemplazo (insumo_viejo, insumo_nuevo, desde, motivo) values
  (16, 17, '2026-10-29', 'Galletas familiares y marineras pasan a la bandeja 17')
on conflict (insumo_viejo) do update set insumo_nuevo = excluded.insumo_nuevo, motivo = excluded.motivo;

-- Mapa insumo por bulto con reemplazos (mismas columnas).
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
select t.producto_codigo, coalesce(r.insumo_nuevo, t.insumo_codigo) as insumo_codigo, sum(t.cantidad) as cantidad
from (select * from ingredientes union all select * from empaque) t
left join core.insumos_reemplazo r on r.insumo_viejo = t.insumo_codigo
group by 1, 2;

-- Prevision con el consumo del reemplazado sumado al nuevo (mismas columnas).
create or replace view calc.prevision_dia as
with fin as (
  select max(fecha) as plan_hasta from core.plan_produccion where fecha >= current_date
), hist as (
  select insumo_codigo, sum(cantidad) / 56.0 as teorico_dia from calc.teorico_real group by 1
), ingr as (
  select distinct insumo_codigo from core.recetas
), st as (
  select * from calc.stock_insumos
), rp as (
  -- consumo medido de los insumos reemplazados (ej. bandeja 16 -> 17), que pasa al nuevo
  select r.insumo_nuevo as insumo_codigo, sum(coalesce(v.consumo_diario, 0)) as consumo
  from core.insumos_reemplazo r join st v on v.insumo_codigo = r.insumo_viejo
  group by r.insumo_nuevo
), s as (
  select st.insumo_codigo, st.stock_hoy,
         nullif(coalesce(st.consumo_diario, 0) + coalesce(rp.consumo, 0), 0) as consumo_diario
  from st left join rp on rp.insumo_codigo = st.insumo_codigo
), f as (
  -- mismo calculo que calc.factor_insumo, en linea para no recalcular el stock dos veces
  select s.insumo_codigo, s.stock_hoy, s.consumo_diario, h.teorico_dia,
         case when i.insumo_codigo is not null then 'ingrediente' else 'empaque' end as tipo,
         case
           when i.insumo_codigo is not null then
             case when coalesce(h.teorico_dia, 0) > 0 and s.consumo_diario > 0
                  then least(greatest(s.consumo_diario / h.teorico_dia, 0.8), 1.6)
                  else 1.42 end
           else
             case when coalesce(h.teorico_dia, 0) > 0 and s.consumo_diario > 0
                  then s.consumo_diario / h.teorico_dia end
         end as factor
  from s
  left join hist h on h.insumo_codigo = s.insumo_codigo
  left join ingr i on i.insumo_codigo = s.insumo_codigo
), d as (
  select f.*, fin.plan_hasta, g::date as dia,
         f.factor is not null and fin.plan_hasta is not null and g::date <= fin.plan_hasta
           and (f.tipo = 'ingrediente' or coalesce(f.teorico_dia, 0) > 0) as segun_plan
  from f
  cross join fin
  cross join generate_series(current_date, current_date + 180, interval '1 day') g
)
select d.insumo_codigo, d.dia,
       case when d.segun_plan then coalesce(tp.cantidad, 0) * d.factor
            else coalesce(d.consumo_diario, 0) end as consumo,
       d.segun_plan,
       d.stock_hoy,
       d.factor
from d
left join calc.teorico_plan tp on tp.insumo_codigo = d.insumo_codigo and tp.fecha = d.dia;

select calc.refrescar_insumos();

-- Control: la bandeja 17 y los productos que la usan.
select s.insumo_codigo, s.insumo, s.stock_hoy, s.consumo_diario as consumo_medido_propio,
       s.dias_cobertura_plan, s.estado_plan,
       (select string_agg(producto_codigo::text, ', ' order by producto_codigo)
          from calc.insumo_por_bulto where insumo_codigo = 17) as productos_que_la_usan
from rpt.stock_insumos s
where s.insumo_codigo in (16, 17);
