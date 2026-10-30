-- 029_categorias_insumos.sql
-- Categoria de cada insumo para separar el tablero (pedido de Cuci, 30/10/2026):
-- Insumos (ingredientes), Flexibles, Bandejas, Cajas, Displays y Otros empaques.
-- Regla automatica por el nombre en Compras (o en el conteo), en este orden: "flex" -> Flexibles
-- (gana sobre "bandeja": "Flexible OPP Bandeja Alfajor" es un flexible), "bandeja" -> Bandejas,
-- "caja" -> Cajas, "display" -> Displays, "etiqueta"/"film"/"cinta"/"rollo" -> Otros empaques;
-- el resto -> Insumos. Para corregir uno a mano:
--   insert into core.insumos_config (insumo_codigo, categoria) values (123, 'Cajas')
--   on conflict (insumo_codigo) do update set categoria = excluded.categoria;
-- Se puede volver a ejecutar sin riesgo.

alter table core.insumos_config add column if not exists categoria text
  check (categoria in ('Insumos', 'Flexibles', 'Bandejas', 'Cajas', 'Displays', 'Otros empaques'));

-- 1. Categoria de cada insumo.
create or replace view calc.insumos_categoria as
with nombres as (
  select codigo as insumo_codigo, nombre from core.insumos
  union
  select insumo_codigo, insumo from core.conteo_insumos
)
select n.insumo_codigo,
       coalesce(max(c.categoria),
         case
           when bool_or(n.nombre ~* 'flex') then 'Flexibles'
           when bool_or(n.nombre ~* 'bandeja') then 'Bandejas'
           when bool_or(n.nombre ~* 'caja') then 'Cajas'
           when bool_or(n.nombre ~* 'display|diplay') then 'Displays'
           when bool_or(n.nombre ~* 'etiqueta|film|cinta|rollo') then 'Otros empaques'
           else 'Insumos'
         end) as categoria
from nombres n
left join core.insumos_config c on c.insumo_codigo = n.insumo_codigo
where n.insumo_codigo is not null
group by n.insumo_codigo;

-- 2. Reportes con la categoria (columna nueva al final).
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
       case when m.revisar_estado then 'Inactivo en la planilla pero se consume' end as observacion,
       ca.categoria
from rpt.stock_insumos s
join calc.insumos_modo m on m.insumo_codigo = s.insumo_codigo
left join calc.insumos_categoria ca on ca.insumo_codigo = s.insumo_codigo
where m.modo_efectivo <> 'inactivo';

create or replace view public.reporte_insumos_pedir as
select s.insumo_codigo, s.insumo, s.unidad, s.proveedor_principal, s.stock_hoy, s.consumo_diario,
       s.dias_cobertura_plan, s.fecha_quiebre_plan, s.lead_time,
       s.sugerido_pedir, s.estado_plan,
       case when s.estado_plan = 'sin stock' then 1 else 2 end as prioridad,
       ca.categoria
from rpt.stock_insumos s
join calc.insumos_modo m on m.insumo_codigo = s.insumo_codigo
left join calc.insumos_categoria ca on ca.insumo_codigo = s.insumo_codigo
where m.modo_efectivo = 'regular'
  and s.estado_plan in ('sin stock', 'crítico')
  and coalesce(s.en_camino, 0) = 0;

create or replace view public.reporte_oc_pendientes as
select o.oc, o.insumo_codigo, coalesce(i.nombre, l.insumo) as insumo, o.proveedor,
       o.fecha_pedido, o.fecha_prometida, o.cantidad, l.unidad_insumo as unidad,
       o.atrasada,
       case when o.atrasada then current_date - o.fecha_prometida end as dias_atraso,
       l.estado,
       ca.categoria
from calc.oc_pendientes o
left join core.oc_lineas l on l.oc = o.oc and l.insumo_codigo = o.insumo_codigo
left join core.insumos i on i.codigo = o.insumo_codigo
left join calc.insumos_modo m on m.insumo_codigo = o.insumo_codigo
left join calc.insumos_categoria ca on ca.insumo_codigo = o.insumo_codigo
where coalesce(m.modo_efectivo, 'regular') <> 'inactivo';

revoke all on public.reporte_stock_insumos, public.reporte_insumos_pedir, public.reporte_oc_pendientes
  from anon, authenticated, public;
grant select on public.reporte_stock_insumos, public.reporte_insumos_pedir, public.reporte_oc_pendientes
  to looker_lectura;

-- Control: cuantos por categoria y los empaques, para revisar que esten bien clasificados.
select categoria, count(*)::text as insumos, null as ejemplo from public.reporte_stock_insumos group by categoria
union all
select categoria, insumo_codigo::text, insumo from public.reporte_stock_insumos where categoria <> 'Insumos'
order by 1, 3 nulls first;
