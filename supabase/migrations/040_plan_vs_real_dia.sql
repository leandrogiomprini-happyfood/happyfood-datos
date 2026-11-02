-- 040_plan_vs_real_dia.sql
-- Cuci (01/11/2026): en Looker, plan vs real de octubre no coincidia con lo producido de octubre.
-- Causa: reporte_plan_vs_real esta por SEMANA (lunes); un filtro 1-31 oct toma las semanas que
-- empiezan en octubre (5/10 a 1/11) y deja afuera del 1 al 4 de octubre.
-- Nueva vista por DIA, para comparar cualquier periodo (mes, rango de fechas) sin cortes:
--   public.reporte_plan_vs_real_dia   fecha, semana, mes, producto, bultos/kilos plan y real
-- La vista semanal (reporte_plan_vs_real) queda para el resultado por semana (Cumplido, etc.).
-- Se puede volver a ejecutar sin riesgo.

create or replace view public.reporte_plan_vs_real_dia as
with plan as (
  select pl.fecha, pl.producto_codigo,
         max(pl.producto) as producto_plan,
         sum(pl.bultos) as bultos_plan,
         sum(coalesce(pl.kilos, pl.bultos * prd.kg_por)) as kilos_plan
  from core.plan_produccion pl
  left join core.productos prd on prd.codigo = pl.producto_codigo::text
  where pl.fecha >= date '2025-03-01' and pl.bultos > 0
  group by 1, 2
), real as (
  select fecha, producto_codigo, max(producto) as producto_real, max(familia) as familia,
         sum(bultos) as bultos_real, sum(kilos) as kilos_real
  from calc.produccion_kg
  where es_produccion
  group by 1, 2
)
select coalesce(pl.fecha, r.fecha)                                as fecha,
       date_trunc('week', coalesce(pl.fecha, r.fecha))::date      as semana,
       date_trunc('month', coalesce(pl.fecha, r.fecha))::date     as mes,
       coalesce(pl.producto_codigo, r.producto_codigo)            as producto_codigo,
       coalesce(prd.producto, r.producto_real, pl.producto_plan)  as producto,
       coalesce(prd.familia, r.familia, 'SIN CLASIFICAR')         as familia,
       coalesce(pl.bultos_plan, 0)                                as bultos_plan,
       coalesce(r.bultos_real, 0)                                 as bultos_real,
       round(coalesce(pl.kilos_plan, 0), 1)                       as kilos_plan,
       round(coalesce(r.kilos_real, 0), 1)                        as kilos_real
from plan pl
full join real r on r.fecha = pl.fecha and r.producto_codigo = pl.producto_codigo
left join core.productos prd on prd.codigo = coalesce(pl.producto_codigo, r.producto_codigo)::text;

revoke all on public.reporte_plan_vs_real_dia from anon, authenticated, public;
grant select on public.reporte_plan_vs_real_dia to looker_lectura;

-- Control octubre 2026: tiene que dar los mismos bultos reales que la pagina Producido (4.612,27).
select 'octubre: bultos plan' as que, round(sum(bultos_plan), 2)::text as valor
from public.reporte_plan_vs_real_dia where fecha between '2026-10-01' and '2026-10-31'
union all select 'octubre: bultos real', round(sum(bultos_real), 2)::text
from public.reporte_plan_vs_real_dia where fecha between '2026-10-01' and '2026-10-31'
union all select 'octubre: producido (pagina 1)', round(sum(bultos), 2)::text
from public.reporte_produccion where fecha between '2026-10-01' and '2026-10-31' and cuenta_como_produccion = 'Sí';
