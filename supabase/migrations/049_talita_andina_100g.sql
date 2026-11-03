-- 049_talita_andina_100g.sql
-- Cuci (03/11/2026): el bulto 3161 (Talita Andina x24) pesa 2,4 kg, no 2,16. En la 010 se habia
-- cargado 90 g por unidad tomado de la descripcion de Tekno ("P90GR"); son 100 g como el resto de las
-- talitas familiares. Corrige kilos producidos, kilos vendidos, costo, prevision de insumos y el rinde por masa.
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

update core.productos set gramos_unidad = 100, actualizado = now() where codigo = '3161';

-- El rinde por masa de la Talita Andina (018) se calculo como unidades por masa x 90 g = 43,2 kg.
-- Con 100 g son 48 kg por masa (las mismas 480 unidades, igual que la Talita clasica).
update core.recetas_rinde set kg_producto_por_masa = 48 where producto_receta = 'Talita Andina';

select calc.refrescar_rpt();
select calc.refrescar_insumos();

-- Control: kg por bulto de todos los bultos vigentes, para revisar que no haya otro mal cargado.
select codigo, producto, unidades_por as unidades, gramos_unidad as gramos, kg_por as kg_por_bulto
from core.productos
where nivel = 'bulto' and estado = 'vigente'
order by codigo;
