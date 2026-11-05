-- 051_stock_pt_desde_happy_food_stock.sql
-- Cuci (05/11/2026): "Control de stock-KG" importa todo de "Happy Food - Stock" y solo le agrega kilos y
-- valor. La base pasa a leer la fuente original (050: stock_hf_cd y stock_hf_planta) y calcula kilos y
-- valor con su propio maestro de productos y costos. Validado el 05/11: las dos fuentes daban los mismos
-- bultos por producto (la comparacion no devolvio diferencias).
-- core.stock_pt mantiene las mismas columnas, asi reporte_stock_pt (038) y Looker no cambian.
--   kilos_disponibles = kilos de los lotes que no pasaron su fecha limite de entrega.
--   valor             = kilos x ultimo costo por kg del producto.
-- Las pestañas de Control de stock-KG se dejan de leer (se pueden volver a activar con activa = true).
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

create or replace view core.stock_pt as
select case s.deposito when 'Centro Distribución' then 'cd' else 'planta' end as deposito,
       s.producto_codigo,
       coalesce(prd.producto, s.producto)                         as producto,
       s.vencimiento,
       s.ingreso,
       s.egreso,
       s.ajuste,
       s.total                                                    as bultos,
       round(s.total * prd.kg_por, 3)                             as kilos,
       case when s.fecha_limite_entrega is null or s.fecha_limite_entrega >= current_date
            then round(s.total * prd.kg_por, 3) else 0 end        as kilos_disponibles,
       round(s.total * prd.kg_por * c.costo_kg, 2)                as valor
from core.stock_hf s
left join core.productos prd on prd.codigo = s.producto_codigo::text
left join lateral (
  select ca.costo_kg from core.costos_articulos ca
  where ca.articulo_codigo = lpad(s.producto_codigo::text, 7, '0')
  order by ca.mes desc limit 1
) c on true;

update hojas.fuentes set activa = false where fuente in ('stock_pt_cd', 'stock_pt_planta', 'stock_pt_transito');

-- Control.
select deposito as que, count(*)::text || ' lotes · ' || round(sum(bultos)) || ' bultos · ' || round(sum(kilos)) || ' kg · '
       || round(sum(kilos_disponibles)) || ' kg disponibles' as valor
from core.stock_pt where bultos > 0 group by deposito
union all select 'productos sin kg en el maestro', count(distinct producto_codigo)::text
  from core.stock_pt where bultos > 0 and kilos is null
union all select 'lineas en reporte_stock_pt', count(*)::text from public.reporte_stock_pt;
