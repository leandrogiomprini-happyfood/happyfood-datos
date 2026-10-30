-- 030_faltantes_por_dia.sql
-- Pedido de Cuci (30/10/2026): el tablero tiene que mostrar QUE DIA del plan falta cada insumo.
-- Hasta la 029 el calculo ya descontaba el plan dia por dia, pero:
--   * no sumaba las OC en camino en su fecha de entrega (una OC que llega el martes no cubria el
--     faltante del miercoles en la cuenta);
--   * el reporte mostraba solo "dias de cobertura", no el dia de produccion que se cae ni cuanto falta.
-- Cambios:
--   1. calc.saldo_dia: stock dia por dia = stock hoy + OC que llegan (fecha prometida, no atrasadas)
--      - consumo previsto (plan; despues del plan, promedio medido).
--   2. La fecha de quiebre y el estado con plan pasan a usar ese saldo (con las OC).
--   3. rpt.faltantes_plan + public.reporte_faltantes_plan: cada dia del plan en que un insumo no
--      alcanza, con lo que se necesita, lo disponible, lo que falta y los productos del plan de ese dia.
-- Las OC atrasadas NO se suman (no se sabe cuando llegan); se ven en reporte_oc_pendientes.
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- 1. Saldo dia por dia con las OC.
create or replace view calc.saldo_dia as
with oc as (
  select insumo_codigo, fecha_prometida as dia, sum(cantidad) as llega
  from calc.oc_pendientes
  where not atrasada and fecha_prometida >= current_date
  group by 1, 2
), p as (
  select d.insumo_codigo, d.dia, d.consumo, d.segun_plan, d.stock_hoy, coalesce(oc.llega, 0) as llega
  from calc.prevision_dia d
  left join oc on oc.insumo_codigo = d.insumo_codigo and oc.dia = d.dia
)
select insumo_codigo, dia, consumo, segun_plan, llega, stock_hoy,
       stock_hoy + sum(llega - consumo) over w + consumo as disponible_inicio,
       stock_hoy + sum(llega - consumo) over w             as saldo_fin
from p
window w as (partition by insumo_codigo order by dia);

-- 2. Fecha de quiebre con las OC (mismas columnas que antes).
create or replace view calc.prevision_insumos as
select insumo_codigo,
       min(dia) filter (where saldo_fin < 0 and consumo > 0)   as fecha_quiebre_plan,
       bool_or(segun_plan)                                      as usa_plan,
       round(sum(consumo) filter (where segun_plan), 3)         as consumo_plan,
       max(dia) filter (where segun_plan)                       as plan_hasta
from calc.saldo_dia
group by insumo_codigo;

-- 3. Faltantes por dia de produccion.
create or replace view calc.faltantes_plan as
with prod as (
  select pl.fecha, ipb.insumo_codigo,
         string_agg(distinct pl.producto_codigo || ' ' || coalesce(pl.producto, '') || ' (' || round(pl.bultos) || ' b)', ' · ') as productos
  from core.plan_produccion pl
  join calc.insumo_por_bulto ipb on ipb.producto_codigo = pl.producto_codigo
  where pl.fecha >= current_date and pl.bultos > 0
  group by 1, 2
)
select s.dia                                  as fecha,
       s.insumo_codigo,
       st.insumo, st.unidad,
       round(s.consumo, 2)                    as necesita,
       round(greatest(s.disponible_inicio, 0), 2) as disponible,
       round(-s.saldo_fin, 2)                 as falta,
       round(s.llega, 2)                      as llega_ese_dia,
       pr.productos,
       st.proveedor_principal, st.lead_time,
       s.dia - current_date                   as dias_hasta
from calc.saldo_dia s
join calc.stock_insumos st on st.insumo_codigo = s.insumo_codigo
left join prod pr on pr.insumo_codigo = s.insumo_codigo and pr.fecha = s.dia
where s.segun_plan and s.consumo > 0 and s.saldo_fin < 0
  and st.modo = 'regular';

-- 4. Resultado guardado y recalculo (se agrega a calc.refrescar_insumos).
drop view if exists public.reporte_faltantes_plan;
drop materialized view if exists rpt.faltantes_plan;
create materialized view rpt.faltantes_plan as select * from calc.faltantes_plan with no data;

create or replace function calc.refrescar_insumos()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare t0 timestamptz := clock_timestamp();
begin
  refresh materialized view rpt.stock_insumos;
  refresh materialized view rpt.faltantes_plan;
  insert into rpt.ultimo_recalculo_insumos (id, fecha, duracion_s)
  values (1, now() at time zone 'America/Argentina/Cordoba', extract(epoch from clock_timestamp() - t0))
  on conflict (id) do update set fecha = excluded.fecha, duracion_s = excluded.duracion_s;
end $$;
revoke all on function calc.refrescar_insumos() from public, anon, authenticated;

select calc.refrescar_insumos();

create or replace view public.reporte_faltantes_plan as
select f.*, ca.categoria
from rpt.faltantes_plan f
left join calc.insumos_modo m on m.insumo_codigo = f.insumo_codigo
left join calc.insumos_categoria ca on ca.insumo_codigo = f.insumo_codigo
where coalesce(m.modo_efectivo, 'regular') = 'regular';

revoke all on public.reporte_faltantes_plan from anon, authenticated, public;
grant select on rpt.faltantes_plan, public.reporte_faltantes_plan to looker_lectura;

-- Control: faltantes del plan, el primer dia de cada insumo.
select distinct on (insumo_codigo)
       fecha, insumo_codigo, insumo, unidad, necesita, disponible, falta, productos
from public.reporte_faltantes_plan
order by insumo_codigo, fecha;
