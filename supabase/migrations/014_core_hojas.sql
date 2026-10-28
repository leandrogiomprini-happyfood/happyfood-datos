-- 014_core_hojas.sql
-- Traduce las fotos de las planillas (hojas.filas, migracion 012) a vistas con columnas con nombre.
--
--   hojas.encabezados  en que fila esta el encabezado de cada pestaña
--   hojas.tabla        cada fila como objeto JSON {"Encabezado": valor}; si un encabezado se repite
--                      se numera ("COD #1", "COD #2"). Si alguien mueve columnas, las vistas siguen
--                      andando porque buscan por nombre de encabezado, no por posicion.
--   core.*             vistas tipadas: insumos, proveedores, produccion, masas, plan, recetas,
--                      conteo de insumos, stock de producto terminado y pedidos.
--
-- Pendiente para la 015: ordenes de compra (OC_DETALLE) y el calculo de stock de insumos.
-- Se puede volver a ejecutar sin riesgo.

-- 1. Conversores para valores de planilla (numero JSON, o texto "12,5" / "dd/mm/aaaa").
create or replace function hojas.num(v jsonb)
returns numeric
language sql
immutable
as $$
  select case
    when v is null then null
    when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric
    when jsonb_typeof(v) = 'string' and btrim(v #>> '{}') ~ '^-?[0-9]+([.,][0-9]+)?$'
      then replace(btrim(v #>> '{}'), ',', '.')::numeric
    else null
  end
$$;

create or replace function hojas.txt(v jsonb)
returns text
language sql
immutable
as $$
  select nullif(btrim(v #>> '{}'), '')
$$;

-- Fechas como las muestra Sheets en Argentina: d/m/aaaa, opcionalmente con hora.
-- Años fuera de 2015-2100 (ej. "12/07/0251", tipeos) devuelven NULL.
create or replace function hojas.fecha(v jsonb)
returns date
language plpgsql
immutable
as $$
declare
  m text[];
begin
  if v is null or jsonb_typeof(v) <> 'string' then return null; end if;
  m := regexp_match(btrim(v #>> '{}'), '^(\d{1,2})/(\d{1,2})/(\d{4})');
  if m is null or m[3]::int not between 2015 and 2100 then return null; end if;
  return make_date(m[3]::int, m[2]::int, m[1]::int);
exception when others then
  return null;
end $$;

-- 2. Fila de encabezado de cada pestaña.
create table if not exists hojas.encabezados (
  fuente           text primary key references hojas.fuentes(fuente) on delete cascade,
  fila_encabezado  int not null check (fila_encabezado >= 1)
);
alter table hojas.encabezados enable row level security;
revoke all on hojas.encabezados from anon, authenticated;

insert into hojas.encabezados (fuente, fila_encabezado) values
  ('compras_insumos', 1), ('compras_oc', 2), ('compras_prov_alim', 1), ('compras_prov_noalim', 1),
  ('conteo_stock', 3), ('insumos_activos', 1), ('pedidos_detalle', 1), ('pedidos_ordenes', 1),
  ('pedidos_pend_kg', 1), ('pedidos_productos', 1), ('plan_semanal', 3), ('produccion_masas', 1),
  ('produccion_partes', 1), ('recetas', 3), ('recetas_kg_producto', 1),
  ('stock_pt_cd', 3), ('stock_pt_planta', 3), ('stock_pt_transito', 3)
on conflict (fuente) do update set fila_encabezado = excluded.fila_encabezado;

-- 3. Cada fila como objeto con los nombres del encabezado.
create or replace view hojas.columnas as
with enc as (
  select e.fuente, f.valores
  from hojas.encabezados e
  join hojas.filas f on f.fuente = e.fuente and f.fila = e.fila_encabezado
), c as (
  select enc.fuente, (x.ord - 1)::int as idx,
         coalesce(nullif(btrim(regexp_replace(x.v #>> '{}', '\s+', ' ', 'g')), ''), 'col' || x.ord) as nombre
  from enc, jsonb_array_elements(enc.valores) with ordinality as x(v, ord)
)
select fuente, idx,
       case when count(*) over (partition by fuente, nombre) > 1
            then nombre || ' #' || row_number() over (partition by fuente, nombre order by idx)
            else nombre end as clave
from c;

create or replace view hojas.tabla as
select f.fuente, f.fila,
       jsonb_object_agg(c.clave, f.valores -> c.idx) as datos,
       f.valores
from hojas.filas f
join hojas.encabezados e on e.fuente = f.fuente and f.fila > e.fila_encabezado
join hojas.columnas c on c.fuente = f.fuente and c.idx < jsonb_array_length(f.valores)
where jsonb_typeof(f.valores -> c.idx) <> 'null'
group by f.fuente, f.fila, f.valores;

-- 4. Insumos (Compras R-COM02, pestaña INSUMOS).
create or replace view core.insumos as
select hojas.num(datos -> 'Nº')::int           as codigo,
       hojas.txt(datos -> 'Nombre')             as nombre,
       hojas.txt(datos -> 'Unidad')             as unidad,
       hojas.txt(datos -> 'Estado')             as estado,
       hojas.txt(datos -> 'Alimenticio?') = 'SI' as alimenticio,
       hojas.num(datos -> 'PU USD')             as precio_usd
from hojas.tabla
where fuente = 'compras_insumos' and hojas.num(datos -> 'Nº') is not null;

-- 5. Insumo-proveedor (alimenticios y no alimenticios). "Cant Receta / Venta" = cuantas unidades de
--    receta trae cada unidad de compra (ej. bidon de 10 LT = 9,7 KG).
create or replace view core.insumos_proveedores as
select case when fuente = 'compras_prov_alim' then 'alimenticio' else 'no alimenticio' end as grupo,
       hojas.num(datos -> 'Cod')::int                 as insumo_codigo,
       hojas.txt(datos -> 'Insumo Receta')             as insumo,
       hojas.txt(datos -> 'Clave')                     as presentacion,
       hojas.txt(datos -> 'Estado #1')                 as estado_proveedor,
       hojas.txt(datos -> 'Estado #2')                 as estado_insumo,
       hojas.txt(datos -> 'Proveedores')               as proveedor,
       hojas.txt(datos -> 'Marca')                     as marca,
       hojas.txt(datos -> 'Tipo')                      as tipo,
       hojas.txt(datos -> 'Unidad Venta')              as unidad_compra,
       hojas.num(datos -> 'Cant Venta')                as cantidad_compra,
       hojas.txt(datos -> 'Unidad Insumo')             as unidad_receta,
       hojas.num(datos -> 'Cant Receta / Venta')       as factor_receta,
       hojas.fecha(datos -> 'Fecha Evaluación')        as fecha_evaluacion,
       hojas.fecha(datos -> 'Fecha Obsoleto')          as fecha_obsoleto
from hojas.tabla
where fuente in ('compras_prov_alim', 'compras_prov_noalim') and hojas.num(datos -> 'Cod') is not null;

-- 6. Parte diario de produccion (PRODUCCIÓN, pestaña Producción).
--    Tipo de Producto "Rearmado": la columna V (indice 21) trae el codigo desarmado (diseño §17).
create or replace view core.produccion_partes as
select fila,
       hojas.fecha(datos -> 'Fecha Producción')       as fecha,
       hojas.fecha(datos -> 'Marca temporal')         as fecha_carga,
       hojas.txt(datos -> 'Lugar')                    as lugar,
       hojas.txt(datos -> 'Responsable')              as responsable,
       hojas.txt(datos -> 'Tipo de Producto')         as tipo,
       hojas.num(datos -> 'COD')::int                 as producto_codigo,
       hojas.txt(datos -> 'Producto')                 as producto,
       hojas.num(datos -> 'Cantidad de Bultos')       as bultos,
       hojas.txt(datos -> 'Lote')                     as lote,
       hojas.fecha(datos -> 'Fecha Vencimiento')      as vencimiento,
       hojas.num(datos -> 'Scrap flexible')           as scrap_flexible,
       hojas.num(datos -> 'Scrap de Producto Terminado') as scrap_producto,
       case when hojas.txt(datos -> 'Tipo de Producto') ilike 'rearmad%'
            then hojas.num(valores -> 21)::int end    as codigo_desarmado
from hojas.tabla
where fuente = 'produccion_partes' and hojas.num(datos -> 'COD') is not null;

-- 7. Declaracion de masas (PRODUCCIÓN, pestaña Producción_Masas).
create or replace view core.produccion_masas as
select fila,
       hojas.fecha(datos -> 'Marca temporal')                          as fecha,
       substring(hojas.txt(datos -> 'Producto') from '^(M-\d+)')       as masa_codigo,
       hojas.txt(datos -> 'Producto')                                  as masa,
       hojas.num(datos -> 'Cantidad de Masa / Premezcla (UN)')         as masas,
       hojas.num(datos -> 'Scrap de Masa (KG)')                        as scrap_kg,
       hojas.txt(datos -> 'Observaciones')                             as observaciones
from hojas.tabla
where fuente = 'produccion_masas' and hojas.num(datos -> 'Cantidad de Masa / Premezcla (UN)') is not null;

-- 8. Plan de produccion semanal. Los encabezados de la planilla estan corridos respecto de los datos,
--    por eso se lee por posicion (traspaso §3: B fecha, D accion, E codigo, H bultos, I kilos, J masas).
create or replace view core.plan_produccion as
select fila,
       hojas.fecha(valores -> 1)            as fecha,
       hojas.txt(valores -> 3)              as accion,
       hojas.num(valores -> 4)::int         as producto_codigo,
       hojas.txt(valores -> 5)              as categoria,
       hojas.txt(valores -> 6)              as producto,
       hojas.num(valores -> 7)              as bultos,
       hojas.num(valores -> 8)              as kilos,
       hojas.num(valores -> 9)              as masas
from hojas.tabla
where fuente = 'plan_semanal' and hojas.num(valores -> 4) is not null and hojas.fecha(valores -> 1) is not null;

-- 9. Recetas oficiales (Control Stock de Insumos.xlsx, pestaña Recetas): matriz insumo x producto.
--    Fila 3 = productos (B a R), columna S = codigo de insumo. Filas 43-48 = kg por UNIDAD
--    (rellenos y baños); el resto = kg por MASA (traspaso §3).
create or replace view core.recetas as
with prod as (
  select (x.ord - 1)::int as idx, btrim(x.v #>> '{}') as producto_receta
  from hojas.filas f, jsonb_array_elements(f.valores) with ordinality as x(v, ord)
  where f.fuente = 'recetas' and f.fila = 3 and x.ord between 2 and 18
)
select r.fila,
       p.producto_receta,
       hojas.num(r.valores -> 18)::int        as insumo_codigo,
       hojas.txt(r.valores -> 0)              as insumo,
       case when r.fila between 43 and 48 then 'kg_por_unidad' else 'kg_por_masa' end as base,
       hojas.num(r.valores -> p.idx)          as kg
from hojas.filas r
join prod p on true
where r.fuente = 'recetas' and r.fila between 4 and 48
  and hojas.num(r.valores -> 18) is not null
  and coalesce(hojas.num(r.valores -> p.idx), 0) <> 0;

-- 10. Conteo semanal de insumos (ConteoStockMPyEnvases). Desde la columna G, un bloque de 4 columnas
--     por fecha: la primera es el total contado (en la unidad del insumo), las otras 3 son la carga.
create or replace view core.conteo_insumos as
with fechas as (
  select (x.ord - 1)::int as idx, hojas.fecha(x.v) as fecha
  from hojas.filas f, jsonb_array_elements(f.valores) with ordinality as x(v, ord)
  where f.fuente = 'conteo_stock' and f.fila = 3 and x.ord >= 7 and (x.ord - 7) % 4 = 0
)
select hojas.num(r.valores -> 0)::int  as insumo_codigo,
       hojas.txt(r.valores -> 1)       as insumo,
       fe.fecha,
       hojas.num(r.valores -> fe.idx)  as cantidad
from hojas.filas r
join fechas fe on fe.fecha is not null
where r.fuente = 'conteo_stock' and r.fila > 3
  and hojas.num(r.valores -> 0) is not null
  and hojas.num(r.valores -> fe.idx) is not null;

-- 11. Stock de producto terminado por lote (Control de stock-KG).
create or replace view core.stock_pt as
select replace(fuente, 'stock_pt_', '')            as deposito,
       hojas.num(datos -> 'CODIGO')::int            as producto_codigo,
       hojas.txt(datos -> 'PRODUCTO')               as producto,
       hojas.fecha(datos -> 'Fecha Vencimiento')    as vencimiento,
       hojas.num(datos -> 'Ingreso')                as ingreso,
       hojas.num(datos -> 'Egreso')                 as egreso,
       hojas.num(datos -> 'Ajuste')                 as ajuste,
       hojas.num(datos -> 'Total')                  as bultos,
       hojas.num(datos -> 'KILOS')                  as kilos,
       hojas.num(datos -> 'KILOS DISPONIBLES')      as kilos_disponibles,
       hojas.num(datos -> 'Valor $')                as valor
from hojas.tabla
where fuente like 'stock_pt_%' and coalesce(hojas.num(datos -> 'CODIGO'), 0) > 0;

-- 12. Pedidos (Happy Food - Pedidos).
create or replace view core.pedidos as
select hojas.num(datos -> 'N°')::int                  as pedido,
       hojas.fecha(datos -> 'Fecha')                   as fecha,
       hojas.fecha(datos -> 'Posible Entrega')         as entrega_prevista,
       hojas.txt(datos -> 'Cliente')                   as cliente,
       hojas.txt(datos -> 'Orden de Compra')           as orden_compra,
       hojas.txt(datos -> 'Tipo')                      as tipo_cliente,
       hojas.txt(datos -> 'Estado')                    as estado,
       hojas.num(datos -> 'Total Bultos')              as bultos,
       hojas.txt(datos -> 'Remito N°')                 as remito,
       hojas.num(datos -> 'Valor Declarado')           as valor_declarado,
       hojas.txt(datos -> 'Lista Precio')              as lista_precio,
       hojas.txt(datos -> 'Tipo Facturación')          as tipo_facturacion,
       hojas.txt(datos -> 'N° Factura')                as factura
from hojas.tabla
where fuente = 'pedidos_ordenes' and hojas.num(datos -> 'N°') is not null;

create or replace view core.pedidos_detalle as
select hojas.txt(datos -> 'COD')                     as linea,
       hojas.num(datos -> 'N° OP')::int               as pedido,
       hojas.fecha(datos -> 'Fecha')                  as fecha,
       hojas.txt(datos -> 'Cliente')                  as cliente,
       hojas.num(datos -> 'Código')::int              as producto_codigo,
       hojas.txt(datos -> 'Producto')                 as producto,
       hojas.txt(datos -> 'Tipo Cliente')             as tipo_cliente,
       hojas.num(datos -> 'Cant. Solicitada')         as solicitado,
       hojas.num(datos -> 'Cant. Preparada')          as preparado
from hojas.tabla
where fuente = 'pedidos_detalle' and hojas.num(datos -> 'N° OP') is not null;

-- 13. Envases por producto (Reporte de pedidos pendientes, hoja KG; traspaso §6).
create or replace view core.envases_producto as
select hojas.num(datos -> 'COD')::int               as producto_codigo,
       hojas.txt(datos -> 'DESCRIP')                 as producto,
       hojas.num(datos -> 'KG')                      as kg_por_bulto,
       hojas.txt(datos -> 'CATEGORIA')               as categoria,
       hojas.txt(datos -> 'Presentación')            as presentacion,
       hojas.num(datos -> 'Codigo de bandeja')::int  as bandeja,
       hojas.num(datos -> 'Codigo display')::int     as display,
       hojas.num(datos -> 'Codigo flexible 1')::int  as flexible_1,
       hojas.num(datos -> 'Codigo flexible 2')::int  as flexible_2
from hojas.tabla
where fuente = 'pedidos_pend_kg' and hojas.num(datos -> 'COD') is not null;

-- 14. Ajuste al maestro de productos (010/011): la hoja KG del reporte de pedidos pendientes dice
--     "BULTO ALFAJOR SOJA DDL X45GR X144UNID." = 6,48 kg para el 9001 (el 9000 viejo era de 50 g).
update core.productos set gramos_unidad = 45,
       envase = 'BULTO DISTRIBUIDOR 144 UNIDADES DE 45 G', actualizado = now()
where codigo = '9001' and gramos_unidad <> 45;
select calc.refrescar_rpt();

-- 15. Permisos: nada de esto es visible por la API publica.
revoke all on all tables in schema hojas from anon, authenticated;
revoke all on core.insumos, core.insumos_proveedores, core.produccion_partes, core.produccion_masas,
  core.plan_produccion, core.recetas, core.conteo_insumos, core.stock_pt, core.pedidos,
  core.pedidos_detalle, core.envases_producto from anon, authenticated;

-- 16. Control: cuantas filas trae cada vista y los encabezados de OC_DETALLE (para la 015).
select 'insumos' as vista, count(*) from core.insumos
union all select 'insumos_proveedores', count(*) from core.insumos_proveedores
union all select 'produccion_partes', count(*) from core.produccion_partes
union all select 'produccion_masas', count(*) from core.produccion_masas
union all select 'plan_produccion', count(*) from core.plan_produccion
union all select 'recetas', count(*) from core.recetas
union all select 'conteo_insumos', count(*) from core.conteo_insumos
union all select 'stock_pt', count(*) from core.stock_pt
union all select 'pedidos', count(*) from core.pedidos
union all select 'pedidos_detalle', count(*) from core.pedidos_detalle
union all select 'envases_producto', count(*) from core.envases_producto
union all select 'ENCABEZADOS OC: ' || string_agg(idx || '=' || clave, ' | ' order by idx), null
  from hojas.columnas where fuente = 'compras_oc'
union all select 'ENCABEZADOS PRODUCCION: ' || string_agg(idx || '=' || clave, ' | ' order by idx), null
  from hojas.columnas where fuente = 'produccion_partes';
