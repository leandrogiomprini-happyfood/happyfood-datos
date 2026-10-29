-- 021_reportes_insumos.sql
-- Vistas para la pagina de insumos en Looker Studio (todas leen resultados ya calculados o tablas
-- chicas, para que Looker responda rapido). Solo lectura para looker_lectura.
--   reporte_stock_insumos   un insumo por fila, con prioridad para ordenar y textos listos
--   reporte_insumos_pedir   "pedir ya": critico o sin stock con el plan y sin OC en camino
--   reporte_oc_pendientes   OC en camino, con dias de atraso
--   reporte_estado_insumos  frescura de los datos: ultimo conteo, plan, lecturas, recalculo
-- Se puede volver a ejecutar sin riesgo.

-- 1. Stock por insumo (misma informacion de la 019/020 + columnas para Looker al final).
create or replace view public.reporte_stock_insumos as
select s.*,
       case s.estado_plan
         when 'sin stock' then 1 when 'crítico' then 2 when 'atención' then 3
         when 'ok' then 4 when 'sin consumo' then 5 else 6 end           as prioridad,
       case when s.en_camino > 0 then 'Sí' else 'No' end                  as tiene_oc_en_camino,
       case when s.dias_cobertura_plan >= 181 then '> 6 meses'
            when s.dias_cobertura_plan is null then '-'
            else s.dias_cobertura_plan::text || ' días' end               as cobertura_texto
from rpt.stock_insumos s;

-- 2. Pedir ya.
create or replace view public.reporte_insumos_pedir as
select insumo_codigo, insumo, unidad, proveedor_principal, stock_hoy, consumo_diario,
       dias_cobertura_plan, fecha_quiebre_plan, lead_time,
       sugerido_pedir, estado_plan,
       case when estado_plan = 'sin stock' then 1 else 2 end as prioridad
from rpt.stock_insumos
where modo = 'regular'
  and estado_plan in ('sin stock', 'crítico')
  and coalesce(en_camino, 0) = 0;

-- 3. OC en camino.
create or replace view public.reporte_oc_pendientes as
select o.oc, o.insumo_codigo, coalesce(i.nombre, l.insumo) as insumo, o.proveedor,
       o.fecha_pedido, o.fecha_prometida, o.cantidad, l.unidad_insumo as unidad,
       o.atrasada,
       case when o.atrasada then current_date - o.fecha_prometida end as dias_atraso,
       l.estado
from calc.oc_pendientes o
left join core.oc_lineas l on l.oc = o.oc and l.insumo_codigo = o.insumo_codigo
left join core.insumos i on i.codigo = o.insumo_codigo;

-- 4. Frescura de los datos.
create or replace view public.reporte_estado_insumos as
select 'Último conteo válido' as dato, (select max(fecha) from calc.conteo_fechas where valido)::text as valor
union all select 'Plan de producción cargado hasta', (select max(plan_hasta) from rpt.stock_insumos)::text
union all select 'Último recálculo', (select to_char(fecha, 'DD/MM/YYYY HH24:MI') from rpt.ultimo_recalculo_insumos)
union all select 'Última lectura de planillas',
  (select to_char(max(ultima_lectura) at time zone 'America/Argentina/Cordoba', 'DD/MM/YYYY HH24:MI') from hojas.fuentes)
union all select 'Pestañas con error', (select count(*)::text from hojas.fuentes where activa and ultimo_error is not null);

revoke all on public.reporte_stock_insumos, public.reporte_insumos_pedir, public.reporte_oc_pendientes,
  public.reporte_estado_insumos from anon, authenticated, public;
grant select on public.reporte_stock_insumos, public.reporte_insumos_pedir, public.reporte_oc_pendientes,
  public.reporte_estado_insumos to looker_lectura;

-- 5. Control.
select 'pedir ya' as que, count(*)::text as valor from public.reporte_insumos_pedir
union all select 'OC en camino', count(*)::text from public.reporte_oc_pendientes
union all select 'OC atrasadas', count(*)::text from public.reporte_oc_pendientes where atrasada
union all select dato, valor from public.reporte_estado_insumos;
