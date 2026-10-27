-- 011_productos_ajustes.sql
-- Datos confirmados por Cuci el 27/10/2026:
--   * 3153 Marinera familiar clasica y 3173 Marinera familiar andina: bulto de 20 paquetes de 70 g (1,4 kg).
--   * Alfajor de soja (fason): 9000 y 9001 son el mismo producto con codigo duplicado. Queda vigente
--     el 9001 (el que se usa desde abril de 2026); el 9000 pasa a obsoleto. Sus ventas siguen sumando kilos.
-- Requiere haber corrido 010. Se puede volver a ejecutar sin riesgo.

update core.productos set unidades_por = 20, gramos_unidad = 70,
       envase = 'BULTO FAMILIAR 20 PAQUETES DE 70 G', actualizado = now()
where codigo in ('3153', '3173');

update core.productos set estado = 'obsoleto', envase = 'BULTO DISTRIBUIDOR 144 UNIDADES (duplicado de 9001)', actualizado = now()
where codigo = '9000';

update core.productos set producto = producto || ' (fason)', actualizado = now()
where codigo in ('8001', '9000', '9001') and producto not like '%(fason)%';

select calc.refrescar_rpt();

-- Control: los 4 codigos corregidos.
select codigo, producto, envase, unidades_por, gramos_unidad, kg_por, estado
from core.productos where codigo in ('3153', '3173', '9000', '9001') order by codigo;
