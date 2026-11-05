-- 054_plan_vs_real_lugar.sql
-- Cuci (05/11/2026): separar plan vs real por lugar (columna "Lugar" del parte: Planta, deposito...).
-- reporte_plan_vs_real_dia suma la columna lugar al final. El plan es de planta: se compara con lo que
-- se hizo en "Planta"; lo hecho en otro lugar queda en su propia fila con plan 0. Partes sin lugar:
-- "Sin lugar". Totales sin cambios. Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

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
  select fecha, producto_codigo, coalesce(lugar, 'Sin lugar') as lugar,
         max(producto) as producto_real, max(familia) as familia,
         sum(bultos) filter (where es_produccion)                          as bultos_real,
         sum(kilos)  filter (where es_produccion)                          as kilos_real,
         sum(bultos) filter (where es_produccion and tipo = 'Super')       as bultos_super,
         sum(bultos) filter (where es_produccion and tipo = 'Distri')      as bultos_distri,
         sum(bultos) filter (where es_produccion and tipo = 'Semielaborado') as bultos_semielaborado,
         sum(bultos) filter (where tipo = 'Rearmado')                      as bultos_rearmado,
         sum(bultos) filter (where tipo = 'Retrabajo')                     as bultos_retrabajo,
         sum(kilos)  filter (where tipo = 'Rearmado')                      as kilos_rearmado
  from calc.produccion_kg
  group by 1, 2, 3
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
       round(coalesce(r.kilos_rearmado, 0), 1)                    as kilos_rearmado,
       coalesce(r.lugar, 'Planta')                                as lugar
from plan pl
full join real r on r.fecha = pl.fecha and r.producto_codigo = pl.producto_codigo and r.lugar = 'Planta'
left join core.productos prd on prd.codigo = coalesce(pl.producto_codigo, r.producto_codigo)::text;



grant select on public.reporte_plan_vs_real_dia to looker_lectura;

-- Control: por lugar en los ultimos 60 dias (los totales tienen que ser los mismos que antes).
select lugar, round(sum(bultos_plan)) as plan, round(sum(bultos_real), 1) as real,
       round(sum(bultos_rearmado), 1) as rearmado, round(sum(bultos_retrabajo), 1) as retrabajo
from public.reporte_plan_vs_real_dia
where fecha >= current_date - 60
group by lugar order by lugar;
