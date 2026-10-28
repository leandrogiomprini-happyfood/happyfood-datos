-- 015_core_oc_produccion.sql
-- 1. Ordenes de compra y recepciones (Compras R-COM02, OC_DETALLE; encabezado en fila 2).
-- 2. Parte de produccion corregido: el formulario tiene una seccion por tipo de producto, con columnas
--    repetidas ("Producto #1..#4", "Cantidad de Bultos #1..#3", "Cantidad de Bandejas", armados).
--    La 014 leia "Producto" y "Cantidad de Bultos" sin numero y quedaban vacios.
-- 3. Etiqueta del 9000 (soja): es la formula anterior de 50 g, no un duplicado (Cuci, 28/10/2026).
-- Se puede volver a ejecutar sin riesgo.

-- 1. OC. Columnas: Cant #1 = cantidad pedida en unidad de compra (bolsas, bidones); Cant. Solicitada =
--    lo mismo en unidad de insumo (kg); Cant #2 = cantidad recibida. Diseño §11.B y §16: la recibida
--    esta cargada a veces en unidad de compra y a veces ya en kg. Regla: si la recibida supera 1,5 veces
--    lo pedido en unidad de compra, ya esta en unidad de insumo; si no, se multiplica por el factor.
create or replace view core.oc_lineas as
with b as (
  select fila,
         hojas.txt(datos -> 'Estado')                 as estado,
         hojas.txt(datos -> 'COD #1')                 as linea,
         hojas.num(datos -> 'N° OC')::int             as oc,
         hojas.fecha(datos -> 'Fecha')                as fecha_pedido,
         hojas.fecha(datos -> 'Fecha Entrega')        as fecha_prometida,
         hojas.txt(datos -> 'Proveedor')              as proveedor,
         hojas.num(datos -> 'COD #2')::int            as insumo_codigo,
         hojas.txt(datos -> 'Producto')               as insumo,
         hojas.txt(datos -> 'Producto Proveedor')     as presentacion,
         hojas.num(datos -> 'Cant #1')                as pedido_compra,
         hojas.txt(datos -> 'UN Insumo')              as unidad_insumo,
         hojas.num(datos -> 'Cant. Solicitada')       as pedido_insumo,
         hojas.num(datos -> 'PU / UN USD')            as precio_usd_unidad,
         hojas.num(datos -> 'Total Neto')             as total_neto,
         hojas.fecha(datos -> 'Fecha Recep.')         as fecha_recepcion,
         hojas.num(datos -> 'Cant #2')                as recibido_cargado,
         hojas.txt(datos -> 'Lote')                   as lote,
         hojas.fecha(datos -> 'Fecha Venc.')          as vencimiento
  from hojas.tabla
  where fuente = 'compras_oc' and hojas.num(datos -> 'COD #2') is not null
)
select b.*,
       case when b.pedido_compra > 0 then b.pedido_insumo / b.pedido_compra end as factor,
       case
         when b.recibido_cargado is null then null
         when coalesce(b.pedido_compra, 0) = 0 or coalesce(b.pedido_insumo, 0) = 0 then b.recibido_cargado
         when b.pedido_insumo = b.pedido_compra then b.recibido_cargado
         when b.recibido_cargado > b.pedido_compra * 1.5 then b.recibido_cargado
         else b.recibido_cargado * b.pedido_insumo / b.pedido_compra
       end as recibido_insumo,
       (b.recibido_cargado is not null and b.pedido_compra > 0 and b.pedido_insumo <> b.pedido_compra
        and b.recibido_cargado > b.pedido_compra * 1.5) as recepcion_cargada_en_kg,
       case when b.fecha_recepcion is not null and b.fecha_pedido is not null
            then b.fecha_recepcion - b.fecha_pedido end as dias_entrega
from b;

drop view if exists core.produccion_partes;

-- 2. Parte de produccion. cantidad = bultos (o bandejas en los semielaborados 2xxx, diseño §4 regla 3).
create or replace view core.produccion_partes as
select fila,
       hojas.fecha(datos -> 'Fecha Producción')       as fecha,
       hojas.fecha(datos -> 'Marca temporal')         as fecha_carga,
       hojas.txt(datos -> 'Lugar')                    as lugar,
       hojas.txt(datos -> 'Responsable')              as responsable,
       hojas.txt(datos -> 'Tipo de Producto')         as tipo,
       hojas.num(datos -> 'COD')::int                 as producto_codigo,
       hojas.txt(coalesce(datos -> 'Producto', datos -> 'Producto #1', datos -> 'Producto #2', datos -> 'Producto #3',
                          datos -> 'Producto #4', datos -> 'Producto armado')) as producto,
       hojas.num(coalesce(datos -> 'Cantidad de Bultos', datos -> 'Cantidad de Bultos #1', datos -> 'Cantidad de Bultos #2',
                          datos -> 'Cantidad de Bultos #3', datos -> 'Cantidad de Bandejas',
                          datos -> 'Cantidad de Bandejas / Bultos armados')) as cantidad,
       case when datos ? 'Cantidad de Bandejas' then 'bandejas'
            when datos ? 'Cantidad de Bandejas / Bultos armados' then 'armado'
            else 'bultos' end                           as unidad_cantidad,
       hojas.txt(coalesce(datos -> 'Lote #1', datos -> 'Lote #2', datos -> 'Lote #3', datos -> 'Lote #4',
                          datos -> 'Lote armados'))     as lote,
       hojas.fecha(coalesce(datos -> 'Fecha Vencimiento #1', datos -> 'Fecha Vencimiento #2',
                            datos -> 'Fecha Vencimiento #3', datos -> 'Fecha Vencimiento #4',
                            datos -> 'Fecha Vencimiento armados')) as vencimiento,
       hojas.num(coalesce(datos -> 'Scrap flexible #1', datos -> 'Scrap flexible #2', datos -> 'Scrap flexible #3',
                          datos -> 'Scrap flexible #4', datos -> 'Scrap flexible #5')) as scrap_flexible,
       hojas.num(coalesce(datos -> 'Scrap de Producto Terminado #1', datos -> 'Scrap de Producto Terminado #2',
                          datos -> 'Scrap de Producto Terminado #3', datos -> 'Scrap de Producto Terminado #4',
                          datos -> 'Scrap de Producto Terminado #5')) as scrap_producto,
       hojas.num(coalesce(datos -> 'Total Masas #1', datos -> 'Total Masas #2', datos -> 'Total Masas #3',
                          datos -> 'Total Masas #4')) as masas_declaradas,
       hojas.num(datos -> 'COD Desarmado')::int        as codigo_desarmado,
       hojas.num(datos -> 'Cantidad Bultos Desar')     as cantidad_desarmada
from hojas.tabla
where fuente = 'produccion_partes' and hojas.num(datos -> 'COD') is not null;

revoke all on core.oc_lineas, core.produccion_partes from anon, authenticated;

-- 3. Soja: 9000 = formula anterior (50 g); 9001 = formula actual (45 g).
update core.productos set envase = 'BULTO DISTRIBUIDOR 144 UNIDADES DE 50 G (formula anterior)', actualizado = now()
where codigo = '9000';

-- 4. Control.
select 'oc_lineas' as que, count(*)::text as valor from core.oc_lineas
union all select 'oc recibidas', count(*)::text from core.oc_lineas where fecha_recepcion is not null
union all select 'oc recepcion cargada en kg (corregidas)', count(*)::text from core.oc_lineas where recepcion_cargada_en_kg
union all select 'oc pendientes', count(*)::text from core.oc_lineas where fecha_recepcion is null and estado not ilike 'anul%'
union all select 'partes por unidad: ' || unidad_cantidad, count(*)::text from core.produccion_partes group by unidad_cantidad
union all select 'partes sin cantidad', count(*)::text from core.produccion_partes where cantidad is null
union all select 'estados de OC', string_agg(distinct estado, ' | ') from core.oc_lineas
union all select 'tipos de parte', string_agg(distinct tipo, ' | ') from core.produccion_partes;
