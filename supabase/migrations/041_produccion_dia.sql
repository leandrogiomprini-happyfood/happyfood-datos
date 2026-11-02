-- 041_produccion_dia.sql
-- Cuci (01/11/2026): cuanto se trabajo en planta por dia, en produccion y en rearmado, para ver que
-- dias fueron eficientes. Esta vista tiene el lado de lo PRODUCIDO; las personas por dia se suman
-- cuando se conecte la planilla de personal (sin ese dato no hay eficiencia, solo volumen).
--   public.reporte_produccion_dia  un renglon por dia habil con produccion o rearmado
-- nivel_dia compara los kg producidos con el promedio de los 20 dias anteriores con produccion.
-- Se puede volver a ejecutar sin riesgo.

create or replace view public.reporte_produccion_dia as
with d as (
  select fecha,
         sum(kilos)  filter (where es_produccion)                         as kilos_produccion,
         sum(bultos) filter (where es_produccion)                         as bultos_produccion,
         sum(bultos) filter (where es_produccion and tipo = 'Super')      as bultos_super,
         sum(bultos) filter (where es_produccion and tipo = 'Distri')     as bultos_distri,
         sum(bultos) filter (where es_produccion and tipo = 'Semielaborado') as bultos_semielaborado,
         sum(bultos) filter (where not es_produccion and tipo = 'Rearmado')  as bultos_rearmado,
         sum(kilos)  filter (where not es_produccion and tipo = 'Rearmado')  as kilos_rearmado,
         sum(bultos) filter (where tipo = 'Retrabajo')                    as bultos_retrabajo,
         count(distinct producto_codigo) filter (where es_produccion)     as productos_distintos,
         sum(scrap_producto) as scrap_producto,
         sum(scrap_flexible) as scrap_flexible
  from calc.produccion_kg
  group by fecha
), m as (
  select d.*,
         avg(kilos_produccion) over (order by fecha rows between 20 preceding and 1 preceding) as kilos_promedio_20
  from d
)
select fecha,
       date_trunc('week', fecha)::date  as semana,
       date_trunc('month', fecha)::date as mes,
       extract(isodow from fecha)::int  as dia_semana,
       round(coalesce(kilos_produccion, 0), 1)   as kilos_produccion,
       round(coalesce(bultos_produccion, 0), 1)  as bultos_produccion,
       round(coalesce(bultos_super, 0), 1)       as bultos_super,
       round(coalesce(bultos_distri, 0), 1)      as bultos_distri,
       round(coalesce(bultos_semielaborado, 0), 1) as bultos_semielaborado,
       round(coalesce(bultos_rearmado, 0), 1)    as bultos_rearmado,
       round(coalesce(kilos_rearmado, 0), 1)     as kilos_rearmado,
       round(coalesce(bultos_retrabajo, 0), 1)   as bultos_retrabajo,
       productos_distintos,
       round(scrap_producto, 2) as scrap_producto,
       round(scrap_flexible, 2) as scrap_flexible,
       round(kilos_promedio_20, 1) as kilos_promedio_20,
       case when coalesce(kilos_produccion, 0) = 0 then 'Solo rearmado'
            when kilos_promedio_20 is null then '-'
            when kilos_produccion >= 1.2 * kilos_promedio_20 then 'Alto'
            when kilos_produccion <= 0.8 * kilos_promedio_20 then 'Bajo'
            else 'Normal' end as nivel_dia
from m;

revoke all on public.reporte_produccion_dia from anon, authenticated, public;
grant select on public.reporte_produccion_dia to looker_lectura;

-- Control: octubre por dia.
select fecha, kilos_produccion, bultos_produccion, bultos_rearmado, productos_distintos, nivel_dia
from public.reporte_produccion_dia
where fecha between '2026-10-01' and '2026-10-31'
order by fecha;
