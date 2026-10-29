-- 023_estado_insumos_ak.sql
-- Estado Activo/Inactivo de cada insumo tomado de la columna AK de "Control Stock de Insumos.xlsx"
-- (pestañas StkEnvasesFlx y Control Stock en Dias), que Cuci ya mantiene (29/10/2026). Ambas pestañas
-- ya se leen cada 6 horas (fuentes envases_flx e insumos_activos de la 012).
--
-- Regla del estado efectivo de un insumo:
--   1. Lo cargado a mano en core.insumos_config manda (sirve para corregir la planilla).
--   2. Si la columna AK dice "Inactivo" y el insumo NO se consumio en las ultimas 8 semanas: inactivo.
--   3. Si AK dice "Inactivo" pero se sigue consumiendo: se muestra, marcado para revisar (puede ser que
--      el codigo de la planilla no coincida con el de Compras, ej. 225 = "Caja Madre 3D alfajores" en
--      AK y "Caja Terciaria 440x280x80" en Compras).
--   4. Sin marca: activo.
-- Los inactivos no aparecen en los reportes de Looker. Se puede volver a ejecutar sin riesgo.

-- 1. Marca de la columna AK (indice 36). El codigo esta en la columna A.
create or replace view core.insumos_estado_planilla as
select distinct on (hojas.num(f.valores -> 0)::int)
       hojas.num(f.valores -> 0)::int  as insumo_codigo,
       hojas.txt(f.valores -> 1)       as insumo_planilla,
       hojas.txt(f.valores -> 36)      as estado_ak,
       f.fuente
from hojas.filas f
where f.fuente in ('envases_flx', 'insumos_activos')
  and hojas.num(f.valores -> 0) is not null
  and hojas.txt(f.valores -> 36) in ('Activo', 'Inactivo')
order by hojas.num(f.valores -> 0)::int, (hojas.txt(f.valores -> 36) = 'Activo') desc;

-- 2. Estado efectivo.
create or replace view calc.insumos_modo as
select s.insumo_codigo,
       case
         when c.modo is not null then c.modo
         when p.estado_ak = 'Inactivo' and coalesce(s.consumo_diario, 0) = 0 then 'inactivo'
         else 'regular'
       end as modo_efectivo,
       p.estado_ak,
       (c.modo is null and p.estado_ak = 'Inactivo' and coalesce(s.consumo_diario, 0) > 0) as revisar_estado
from rpt.stock_insumos s
left join core.insumos_config c on c.insumo_codigo = s.insumo_codigo
left join core.insumos_estado_planilla p on p.insumo_codigo = s.insumo_codigo;

-- 3. Reportes con el estado efectivo (columnas nuevas al final).
create or replace view public.reporte_stock_insumos as
select s.*,
       case s.estado_plan
         when 'sin stock' then 1 when 'crítico' then 2 when 'atención' then 3
         when 'ok' then 4 when 'sin consumo' then 5 else 6 end           as prioridad,
       case when s.en_camino > 0 then 'Sí' else 'No' end                  as tiene_oc_en_camino,
       case when s.dias_cobertura_plan >= 181 then '> 6 meses'
            when s.dias_cobertura_plan is null then '-'
            else s.dias_cobertura_plan::text || ' días' end               as cobertura_texto,
       m.estado_ak,
       case when m.revisar_estado then 'Inactivo en la planilla pero se consume' end as observacion
from rpt.stock_insumos s
join calc.insumos_modo m on m.insumo_codigo = s.insumo_codigo
where m.modo_efectivo <> 'inactivo';

create or replace view public.reporte_insumos_pedir as
select s.insumo_codigo, s.insumo, s.unidad, s.proveedor_principal, s.stock_hoy, s.consumo_diario,
       s.dias_cobertura_plan, s.fecha_quiebre_plan, s.lead_time,
       s.sugerido_pedir, s.estado_plan,
       case when s.estado_plan = 'sin stock' then 1 else 2 end as prioridad
from rpt.stock_insumos s
join calc.insumos_modo m on m.insumo_codigo = s.insumo_codigo
where m.modo_efectivo = 'regular'
  and s.estado_plan in ('sin stock', 'crítico')
  and coalesce(s.en_camino, 0) = 0;

create or replace view public.reporte_oc_pendientes as
select o.oc, o.insumo_codigo, coalesce(i.nombre, l.insumo) as insumo, o.proveedor,
       o.fecha_pedido, o.fecha_prometida, o.cantidad, l.unidad_insumo as unidad,
       o.atrasada,
       case when o.atrasada then current_date - o.fecha_prometida end as dias_atraso,
       l.estado
from calc.oc_pendientes o
left join core.oc_lineas l on l.oc = o.oc and l.insumo_codigo = o.insumo_codigo
left join core.insumos i on i.codigo = o.insumo_codigo
left join calc.insumos_modo m on m.insumo_codigo = o.insumo_codigo
where coalesce(m.modo_efectivo, 'regular') <> 'inactivo';

revoke all on public.reporte_stock_insumos, public.reporte_insumos_pedir, public.reporte_oc_pendientes
  from anon, authenticated, public;
grant select on public.reporte_stock_insumos, public.reporte_insumos_pedir, public.reporte_oc_pendientes
  to looker_lectura;

-- 4. Control: marcas leidas, ocultos y casos para revisar.
select 'marcas leidas de la columna AK' as que, count(*)::text as valor from core.insumos_estado_planilla
union all select 'insumos ocultos (inactivos)', count(*)::text from calc.insumos_modo where modo_efectivo = 'inactivo'
union all select 'oculto: ' || s.insumo_codigo || ' ' || s.insumo,
                 coalesce(m.estado_ak, '-') || case when c.modo is not null then ' (cargado a mano)' else '' end
  from calc.insumos_modo m join rpt.stock_insumos s using (insumo_codigo)
  left join core.insumos_config c using (insumo_codigo)
  where m.modo_efectivo = 'inactivo'
union all select 'REVISAR: ' || s.insumo_codigo || ' ' || s.insumo || ' / en planilla: ' || coalesce(p.insumo_planilla, '-'),
                 'Inactivo en AK pero consume ' || round(s.consumo_diario, 2) || ' ' || coalesce(s.unidad, '') || '/dia'
  from calc.insumos_modo m join rpt.stock_insumos s using (insumo_codigo)
  join core.insumos_estado_planilla p using (insumo_codigo)
  where m.revisar_estado;
