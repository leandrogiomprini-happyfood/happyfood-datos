-- 052_plan_kilos_desde_maestro.sql
-- Cuci (05/11/2026): en la planilla del plan semanal la columna "kilos - Plan" no siempre coincide con
-- los bultos (ej. 05/11 JAMON 150 bultos = 240 kg; 06/11 QUESO 50 bultos = 240 kg). Los kilos del plan
-- pasan a calcularse como bultos x kg por bulto del maestro, igual que los kilos reales; la columna de la
-- planilla queda solo si el producto no tiene peso en el maestro. Mismas columnas que la 038 y la 044.
-- Se puede volver a ejecutar sin riesgo.

create or replace view public.reporte_plan_vs_real as
with plan as (
  select date_trunc('week', pl.fecha)::date as semana, pl.producto_codigo,
         max(pl.producto) as producto_plan,
         sum(pl.bultos) as bultos_plan,
         sum(coalesce(pl.bultos * prd.kg_por, pl.kilos)) as kilos_plan
  from core.plan_produccion pl
  left join core.productos prd on prd.codigo = pl.producto_codigo::text
  where pl.fecha >= date '2025-03-01' and pl.bultos > 0
  group by 1, 2
), real as (
  select semana, producto_codigo, max(producto) as producto_real, max(familia) as familia,
         sum(bultos) as bultos_real, sum(kilos) as kilos_real
  from calc.produccion_kg
  where es_produccion
  group by 1, 2
)
select coalesce(pl.semana, r.semana)                              as semana,
       coalesce(pl.producto_codigo, r.producto_codigo)            as producto_codigo,
       coalesce(prd.producto, r.producto_real, pl.producto_plan)  as producto,
       coalesce(prd.familia, r.familia, 'SIN CLASIFICAR')         as familia,
       coalesce(pl.bultos_plan, 0)                                as bultos_plan,
       coalesce(r.bultos_real, 0)                                 as bultos_real,
       round(coalesce(pl.kilos_plan, 0), 1)                       as kilos_plan,
       round(coalesce(r.kilos_real, 0), 1)                        as kilos_real,
       case when pl.semana is null then 'Fuera de plan'
            when coalesce(r.bultos_real, 0) = 0 then 'No se hizo'
            when r.bultos_real < 0.9 * pl.bultos_plan then 'Menos que el plan'
            when r.bultos_real > 1.1 * pl.bultos_plan then 'Más que el plan'
            else 'Cumplido' end                                   as resultado,
       coalesce(pl.semana, r.semana) + 6 < current_date           as semana_cerrada
from plan pl
full join real r on r.semana = pl.semana and r.producto_codigo = pl.producto_codigo
left join core.productos prd on prd.codigo = coalesce(pl.producto_codigo, r.producto_codigo)::text;


create or replace view public.reporte_plan_vs_real_dia as
with plan as (
  select pl.fecha, pl.producto_codigo,
         max(pl.producto) as producto_plan,
         sum(pl.bultos) as bultos_plan,
         sum(coalesce(pl.bultos * prd.kg_por, pl.kilos)) as kilos_plan
  from core.plan_produccion pl
  left join core.productos prd on prd.codigo = pl.producto_codigo::text
  where pl.fecha >= date '2025-03-01' and pl.bultos > 0
  group by 1, 2
), real as (
  select fecha, producto_codigo, max(producto) as producto_real, max(familia) as familia,
         sum(bultos) filter (where es_produccion)                          as bultos_real,
         sum(kilos)  filter (where es_produccion)                          as kilos_real,
         sum(bultos) filter (where es_produccion and tipo = 'Super')       as bultos_super,
         sum(bultos) filter (where es_produccion and tipo = 'Distri')      as bultos_distri,
         sum(bultos) filter (where es_produccion and tipo = 'Semielaborado') as bultos_semielaborado,
         sum(bultos) filter (where tipo = 'Rearmado')                      as bultos_rearmado,
         sum(bultos) filter (where tipo = 'Retrabajo')                     as bultos_retrabajo,
         sum(kilos)  filter (where tipo = 'Rearmado')                      as kilos_rearmado
  from calc.produccion_kg
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
       round(coalesce(r.kilos_real, 0), 1)                        as kilos_real,
       coalesce(r.bultos_super, 0)                                as bultos_super,
       coalesce(r.bultos_distri, 0)                               as bultos_distri,
       coalesce(r.bultos_semielaborado, 0)                        as bultos_semielaborado,
       coalesce(r.bultos_rearmado, 0)                             as bultos_rearmado,
       coalesce(r.bultos_retrabajo, 0)                            as bultos_retrabajo,
       round(coalesce(r.kilos_rearmado, 0), 1)                    as kilos_rearmado
from plan pl
full join real r on r.fecha = pl.fecha and r.producto_codigo = pl.producto_codigo
left join core.productos prd on prd.codigo = coalesce(pl.producto_codigo, r.producto_codigo)::text;


grant select on public.reporte_plan_vs_real, public.reporte_plan_vs_real_dia to looker_lectura;

-- Control: hasta que fecha hay plan y el plan de los proximos dias.
select 'plan cargado hasta' as que, max(fecha)::text as valor from core.plan_produccion
union all select * from (
  select to_char(fecha, 'DD/MM') || ' · ' || producto_codigo || ' ' || coalesce(producto, ''),
         bultos_plan || ' bultos · ' || kilos_plan || ' kg'
  from public.reporte_plan_vs_real_dia
  where fecha >= current_date and bultos_plan > 0
  order by fecha, producto_codigo) x;
