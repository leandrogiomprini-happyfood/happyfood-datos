-- 044_plan_vs_real_tipos.sql
-- Cuci (01/11/2026): en la tabla de plan vs real quiere ver que tipo de trabajo se hizo.
-- reporte_plan_vs_real_dia suma columnas al final (las de la 040 no cambian, asi que bultos_real
-- sigue siendo solo produccion nueva y sigue cerrando con la pagina Producido):
--   bultos_super, bultos_distri, bultos_semielaborado  -> desglose de bultos_real
--   bultos_rearmado, bultos_retrabajo                  -> cambios de formato (no suman a bultos_real)
--   kilos_rearmado
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

grant select on public.reporte_plan_vs_real_dia to looker_lectura;

-- Control octubre: bultos_real = super + distri + semielaborado (y = 4.612,27).
select round(sum(bultos_plan)) as plan, round(sum(bultos_real), 2) as real,
       round(sum(bultos_super + bultos_distri + bultos_semielaborado), 2) as suma_tipos,
       round(sum(bultos_super)) as super, round(sum(bultos_distri)) as distri,
       round(sum(bultos_semielaborado)) as semielaborado,
       round(sum(bultos_rearmado)) as rearmado, round(sum(bultos_retrabajo)) as retrabajo
from public.reporte_plan_vs_real_dia
where fecha between '2026-10-01' and '2026-10-31';
