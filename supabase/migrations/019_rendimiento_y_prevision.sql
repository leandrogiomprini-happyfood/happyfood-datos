-- 019_rendimiento_y_prevision.sql
-- Reemplaza a la 018, que dio "upstream timeout" en Supabase (28/10/2026) y no quedo aplicada.
-- Causa: las vistas armaban el objeto {encabezado: valor} de cada fila de planilla en cada consulta,
-- y la prevision recalculaba todo varias veces.
-- Cambios:
--   A. El objeto {encabezado: valor} se arma UNA vez, al guardar cada lectura (columna hojas.filas.datos).
--   B. Prevision con el plan (contenido de la 018, sin cambios de logica).
--   C. El resultado se guarda en una vista materializada (rpt.stock_insumos) que se recalcula a los :10
--      y :40 de cada hora; Looker y las consultas leen ese resultado ya calculado.
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- A1. Columna con la fila ya armada.
alter table hojas.filas add column if not exists datos jsonb;

-- A2. Encabezados de una pestaña (los repetidos se numeran: "COD #1", "COD #2").
create or replace function hojas.columnas_de(p_fuente text)
returns table (idx int, clave text)
language sql
stable
set search_path to ''
as $$
  with enc as (
    select f.valores
    from hojas.encabezados e
    join hojas.filas f on f.fuente = e.fuente and f.fila = e.fila_encabezado
    where e.fuente = p_fuente
  ), c as (
    select (x.ord - 1)::int as idx,
           coalesce(nullif(btrim(regexp_replace(x.v #>> '{}', '\s+', ' ', 'g')), ''), 'col' || x.ord) as nombre
    from enc, jsonb_array_elements(enc.valores) with ordinality as x(v, ord)
  )
  select idx,
         case when count(*) over (partition by nombre) > 1
              then nombre || ' #' || row_number() over (partition by nombre order by idx)
              else nombre end
  from c
$$;

-- A3. Armar el objeto de cada fila de una pestaña.
create or replace function hojas.armar_datos(p_fuente text)
returns int
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_enc int;
  v_n int;
begin
  select fila_encabezado into v_enc from hojas.encabezados where fuente = p_fuente;
  if v_enc is null then return 0; end if;

  create temporary table if not exists tmp_cols (idx int, clave text) on commit drop;
  delete from tmp_cols;
  insert into tmp_cols select * from hojas.columnas_de(p_fuente);

  update hojas.filas f
     set datos = (select jsonb_object_agg(c.clave, f.valores -> c.idx)
                  from tmp_cols c
                  where c.idx < jsonb_array_length(f.valores)
                    and jsonb_typeof(f.valores -> c.idx) <> 'null')
   where f.fuente = p_fuente and f.fila > v_enc;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke all on function hojas.armar_datos(text) from public, anon, authenticated;

-- A4. hojas.cargar arma los objetos despues de guardar una lectura nueva.
create or replace function hojas.cargar(p_fuente text, p_hash text, p_filas jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_hash_ant text;
  v_n int;
begin
  select f.ultimo_hash into v_hash_ant from hojas.fuentes f where f.fuente = p_fuente and f.activa;
  if not found then raise exception 'Fuente no habilitada'; end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then raise exception 'Formato invalido'; end if;
  v_n := jsonb_array_length(p_filas);

  if v_hash_ant is not distinct from p_hash then
    update hojas.fuentes set ultima_lectura = now(), ultimo_error = null where fuente = p_fuente;
    insert into hojas.lecturas (fuente, ok, filas, cambio) values (p_fuente, true, v_n, false);
    return jsonb_build_object('ok', true, 'fuente', p_fuente, 'filas', v_n, 'cambio', false);
  end if;

  delete from hojas.filas where fuente = p_fuente;
  insert into hojas.filas (fuente, fila, valores)
  select p_fuente, (e.n)::int, e.v
  from jsonb_array_elements(p_filas) with ordinality as e(v, n)
  where jsonb_typeof(e.v) = 'array';

  perform hojas.armar_datos(p_fuente);

  update hojas.fuentes
     set ultimo_hash = p_hash, ultima_lectura = now(), ultimo_cambio = now(), ultimo_error = null
   where fuente = p_fuente;
  insert into hojas.lecturas (fuente, ok, filas, cambio) values (p_fuente, true, v_n, true);
  return jsonb_build_object('ok', true, 'fuente', p_fuente, 'filas', v_n, 'cambio', true);
end $$;

revoke all on function hojas.cargar(text, text, jsonb) from public, anon, authenticated;

-- A5. hojas.tabla lee lo ya armado (mismas columnas que en la 014).
create or replace view hojas.tabla as
select f.fuente, f.fila, f.datos, f.valores
from hojas.filas f
join hojas.encabezados e on e.fuente = f.fuente and f.fila > e.fila_encabezado
where f.datos is not null;

-- A6. Armar lo que ya esta cargado. Las 3 pestañas de stock de producto terminado (muy largas) se
--     rearman solas en la proxima lectura (se borra su hash para forzarla).
select fuente, hojas.armar_datos(fuente) as filas_armadas
from hojas.encabezados
where fuente not like 'stock_pt_%';
update hojas.fuentes set ultimo_hash = null where fuente like 'stock_pt_%';

-- B1. Que receta usa cada producto (por los digitos 2 y 3 del codigo: 3001 -> "00" -> DDL).
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

-- B2. Insumo teorico por bulto de cada producto.
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

-- B3. Teorico de las ultimas 8 semanas segun el parte. Las bandejas de semielaborado (2xx1) se pasan
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

-- B4. Stock dia por dia con el plan (180 dias).
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

-- B5. Stock con prevision (columnas nuevas al final).
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

-- C1. Resultado guardado.
drop view if exists public.reporte_stock_insumos;
drop materialized view if exists rpt.stock_insumos;
create materialized view rpt.stock_insumos as select * from calc.stock_insumos_plan;

create table if not exists rpt.ultimo_recalculo_insumos (
  id int primary key default 1 check (id = 1),
  fecha timestamp not null,
  duracion_s numeric not null
);

create or replace function calc.refrescar_insumos()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare t0 timestamptz := clock_timestamp();
begin
  refresh materialized view rpt.stock_insumos;
  insert into rpt.ultimo_recalculo_insumos (id, fecha, duracion_s)
  values (1, now() at time zone 'America/Argentina/Cordoba', extract(epoch from clock_timestamp() - t0))
  on conflict (id) do update set fecha = excluded.fecha, duracion_s = excluded.duracion_s;
end $$;
revoke all on function calc.refrescar_insumos() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'refrescar_insumos';
  perform cron.schedule('refrescar_insumos', '10,40 * * * *', 'select calc.refrescar_insumos()');
end $$;

select calc.refrescar_insumos();

create or replace view public.reporte_stock_insumos as select * from rpt.stock_insumos;
revoke all on public.reporte_stock_insumos from anon, authenticated, public;
grant select on rpt.stock_insumos, public.reporte_stock_insumos to looker_lectura;

-- C2. Control (lee el resultado guardado).
select 'estado con plan: ' || estado_plan as que, count(*)::text as valor
from rpt.stock_insumos group by estado_plan
union all select 'plan cargado hasta', max(plan_hasta)::text from rpt.stock_insumos
union all select 'recalculo (segundos)', duracion_s::text from rpt.ultimo_recalculo_insumos
union all
select * from (
  select 'cambia: ' || insumo || ' (' || insumo_codigo || ')',
         coalesce(dias_cobertura::text, '-') || ' d sin plan -> ' || coalesce(dias_cobertura_plan::text, '-') || ' d con plan'
  from rpt.stock_insumos
  where usa_plan and dias_cobertura is not null and dias_cobertura_plan is not null
  order by abs(dias_cobertura - dias_cobertura_plan) desc
  limit 12
) x;
