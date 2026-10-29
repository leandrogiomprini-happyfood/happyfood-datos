-- 022_insumos_inactivos.sql
-- Insumos que ya no se usan (pedido de Cuci, 29/10/2026): no se muestran en los reportes de insumos.
-- Hasta ahora el calculo tomaba todo lo que figura en el ultimo conteo, porque el "Estado" de Compras
-- no es confiable (diseño §11: 26 codigos que se cuentan figuran OBSOLETO, entre ellos los baños de
-- chocolate) y la marca Activo/Inactivo de la planilla de recetas no cubre todos (194, 195 y 250 sin marca).
-- Mecanismo: modo 'inactivo' en core.insumos_config. Para sumar uno:
--   insert into core.insumos_config (insumo_codigo, modo, motivo) values (123, 'inactivo', 'motivo')
--   on conflict (insumo_codigo) do update set modo = 'inactivo', motivo = excluded.motivo;
--   select calc.refrescar_insumos();
-- Para reactivarlo: update core.insumos_config set modo = 'regular' where insumo_codigo = 123;
-- Se puede volver a ejecutar sin riesgo.

alter table core.insumos_config drop constraint if exists insumos_config_modo_check;
alter table core.insumos_config add constraint insumos_config_modo_check
  check (modo in ('regular', 'por_pedido', 'inactivo'));

insert into core.insumos_config (insumo_codigo, modo, motivo) values
  (59,  'inactivo', 'Display Galleta de Naranja: reemplazado por el diseño 2026 (258)'),
  (194, 'inactivo', 'Copos de avena: no se usa'),
  (195, 'inactivo', 'Avena tradicional: no se usa')
on conflict (insumo_codigo) do update set modo = excluded.modo, motivo = excluded.motivo, actualizado = now();

-- Reportes sin los inactivos (las columnas no cambian).
create or replace view public.reporte_stock_insumos as
select s.*,
       case s.estado_plan
         when 'sin stock' then 1 when 'crítico' then 2 when 'atención' then 3
         when 'ok' then 4 when 'sin consumo' then 5 else 6 end           as prioridad,
       case when s.en_camino > 0 then 'Sí' else 'No' end                  as tiene_oc_en_camino,
       case when s.dias_cobertura_plan >= 181 then '> 6 meses'
            when s.dias_cobertura_plan is null then '-'
            else s.dias_cobertura_plan::text || ' días' end               as cobertura_texto
from rpt.stock_insumos s
where s.modo <> 'inactivo';

create or replace view public.reporte_oc_pendientes as
select o.oc, o.insumo_codigo, coalesce(i.nombre, l.insumo) as insumo, o.proveedor,
       o.fecha_pedido, o.fecha_prometida, o.cantidad, l.unidad_insumo as unidad,
       o.atrasada,
       case when o.atrasada then current_date - o.fecha_prometida end as dias_atraso,
       l.estado
from calc.oc_pendientes o
left join core.oc_lineas l on l.oc = o.oc and l.insumo_codigo = o.insumo_codigo
left join core.insumos i on i.codigo = o.insumo_codigo
left join core.insumos_config c on c.insumo_codigo = o.insumo_codigo
where coalesce(c.modo, 'regular') <> 'inactivo';

select calc.refrescar_insumos();

-- Candidatos a revisar: sin consumo medido en 8 semanas, o en cero sin OC, o OBSOLETO en Compras.
select s.insumo_codigo, s.insumo, s.unidad, s.stock_hoy, s.consumo_diario, s.estado_plan,
       i.estado as estado_compras
from rpt.stock_insumos s
left join core.insumos i on i.codigo = s.insumo_codigo
where s.modo = 'regular'
  and (coalesce(s.consumo_diario, 0) = 0
       or (s.stock_hoy = 0 and coalesce(s.en_camino, 0) = 0)
       or i.estado ilike 'obsoleto%')
order by s.insumo_codigo;
