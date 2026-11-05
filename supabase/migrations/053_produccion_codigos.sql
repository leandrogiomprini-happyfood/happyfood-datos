-- 053_produccion_codigos.sql
-- Cuci (05/11/2026): en el informe diario hace falta ver que codigos se hicieron.
-- reporte_produccion suma al final:
--   codigo_parte      el codigo tal como se cargo en el parte (ej. 2101 bandejas); producto_codigo
--                     sigue siendo el bulto al que se convierte (3101), para cruzar con plan y ventas
--   unidad_cantidad   bultos, bandejas o armado
--   cantidad_parte    la cantidad tal como se cargo (bandejas o bultos)
--   codigo_desarmado  en los rearmados: el codigo que se desarmo para armar este
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

create or replace view calc.produccion_kg as
with p as (
  select pp.*,
         case when pp.unidad_cantidad = 'bandejas'
              then ('3' || substring(lpad(pp.producto_codigo::text, 4, '0'), 2, 3))::int
              else pp.producto_codigo end as producto_bulto,
         case when pp.unidad_cantidad = 'bandejas' then pp.cantidad / 30.0 else pp.cantidad end as bultos_eq
  from core.produccion_partes pp
  where pp.fecha >= date '2025-03-01' and pp.fecha <= current_date and pp.cantidad > 0
)
select p.fila, p.fecha,
       date_trunc('week', p.fecha)::date                         as semana,
       date_trunc('month', p.fecha)::date                        as mes,
       p.producto_bulto                                          as producto_codigo,
       coalesce(prd.producto, p.producto)                        as producto,
       coalesce(prd.familia, 'SIN CLASIFICAR')                   as familia,
       p.unidad_cantidad,
       coalesce(p.tipo, '')                                      as tipo,
       p.unidad_cantidad <> 'armado'
         and coalesce(p.tipo, '') not in ('Rearmado', 'Retrabajo') as es_produccion,
       p.cantidad                                                as cantidad_parte,
       round(p.bultos_eq, 3)                                     as bultos,
       round(p.bultos_eq * prd.kg_por, 3)                        as kilos,
       coalesce(p.scrap_producto, 0)                             as scrap_producto,
       coalesce(p.scrap_flexible, 0)                             as scrap_flexible,
       p.masas_declaradas,
       p.lugar, p.responsable, p.lote, p.vencimiento,
       p.producto_codigo                                         as codigo_parte,
       p.codigo_desarmado
from p
left join core.productos prd on prd.codigo = p.producto_bulto::text;


create or replace view public.reporte_produccion as
select fecha, semana, mes, producto_codigo, producto, familia,
       case when tipo = '' then 'Sin tipo' else tipo end            as clase,
       bultos, kilos, scrap_producto, scrap_flexible, masas_declaradas,
       lugar, responsable, lote, vencimiento,
       case when es_produccion then 'Sí' else 'No' end               as cuenta_como_produccion,
       codigo_parte, unidad_cantidad, cantidad_parte, codigo_desarmado
from calc.produccion_kg;


grant select on public.reporte_produccion to looker_lectura;

-- Control: lo que se hizo ayer y hoy.
select fecha, clase, codigo_parte, producto, unidad_cantidad, cantidad_parte, bultos, kilos, codigo_desarmado
from public.reporte_produccion
where fecha >= current_date - 1
order by fecha, clase, codigo_parte;
