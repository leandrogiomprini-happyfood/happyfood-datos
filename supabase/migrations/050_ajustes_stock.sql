-- 050_ajustes_stock.sql
-- Ajustes de stock de producto terminado (pedido de Cuci, 05/11/2026) y el stock que calcula la
-- planilla "Happy Food - Stock" con esos ajustes, la produccion, las transferencias y los pedidos.
-- Fuentes (Google Sheets, compartidas como Lector con la cuenta de servicio):
--   ajustes_stock    "Happy Food - Ajuste Stock", pestaña DETALLE: un renglon por producto de cada
--                    ajuste (N°, fecha, motivo, quien retira, ingreso/egreso, deposito, vencimiento, cantidad)
--   stock_hf_cd      "Happy Food - Stock", pestaña STOCK_CD: stock por lote del centro de distribucion
--   stock_hf_planta  "Happy Food - Stock", pestaña STOCK_Planta: stock por lote de planta
-- La cantidad esta en la unidad del codigo (bulto, display o bandeja); los kg salen del maestro de
-- productos y el valor del costo por kg del mes (core.costos_articulos).
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- 1. Planillas.
insert into hojas.fuentes (fuente, planilla_id, hoja, tipo, descripcion, cada_minutos) values
  ('ajustes_stock',   '1CD4QPDxsz0DOkEyxwwmD_atkkpo5rN5zuv0H8WuQEj0', 'DETALLE', 'sheet',
   'Ajustes de stock de PT (regalo, muestra, decomiso, diferencia de inventario, rearmados...)', 60),
  ('stock_hf_cd',     '1zAilIUUZq-KzrdCxkWaR6JXWHb4y8yVjQ8OMtOiupsI', 'STOCK_CD', 'sheet',
   'Happy Food - Stock: stock por lote del centro de distribucion', 60),
  ('stock_hf_planta', '1zAilIUUZq-KzrdCxkWaR6JXWHb4y8yVjQ8OMtOiupsI', 'STOCK_Planta', 'sheet',
   'Happy Food - Stock: stock por lote de planta', 60)
on conflict (fuente) do update set planilla_id = excluded.planilla_id, hoja = excluded.hoja, tipo = excluded.tipo,
  descripcion = excluded.descripcion, cada_minutos = excluded.cada_minutos;

insert into hojas.encabezados (fuente, fila_encabezado) values
  ('ajustes_stock', 1), ('stock_hf_cd', 1), ('stock_hf_planta', 1)
on conflict (fuente) do update set fila_encabezado = excluded.fila_encabezado;

-- 2. Ajustes (DETALLE tiene dos columnas "Producto": la primera es "codigo - nombre", la segunda el nombre).
create or replace view core.ajustes_stock as
select hojas.txt(datos -> 'COD')                        as renglon,
       hojas.num(datos -> 'N°')::int                    as ajuste,
       hojas.fecha(datos -> 'Fecha')                    as fecha,
       hojas.txt(datos -> 'Motivo')                     as motivo,
       hojas.txt(datos -> 'Quien Retira')               as quien,
       hojas.txt(datos -> 'Tipo')                       as tipo,
       hojas.txt(datos -> 'Depósito')                   as deposito,
       hojas.num(datos -> 'Código')::int                as producto_codigo,
       coalesce(hojas.txt(datos -> 'Producto #2'), hojas.txt(datos -> 'Producto #1')) as producto,
       hojas.fecha(datos -> 'Fecha Venc')               as vencimiento,
       hojas.num(datos -> 'Cant.')                      as cantidad,
       case when hojas.txt(datos -> 'Tipo') = 'Egreso' then -1 else 1 end * hojas.num(datos -> 'Cant.') as cantidad_signo,
       nullif(hojas.txt(datos -> 'Observación'), '-')   as observacion
from hojas.tabla
where fuente = 'ajustes_stock'
  and hojas.num(datos -> 'Código') is not null
  and hojas.txt(datos -> 'Tipo') in ('Ingreso', 'Egreso');

-- 3. Stock de "Happy Food - Stock" por lote (lo disponible para la venta).
create or replace view core.stock_hf as
select case when fuente = 'stock_hf_cd' then 'Centro Distribución' else 'Planta' end as deposito,
       hojas.num(datos -> 'CODIGO')::int                     as producto_codigo,
       hojas.txt(datos -> 'PRODUCTO')                        as producto,
       hojas.fecha(datos -> 'Fecha Vencimiento')             as vencimiento,
       hojas.num(datos -> 'Ingreso')                         as ingreso,
       hojas.num(datos -> 'Egreso')                          as egreso,
       hojas.num(datos -> 'Ajuste')                          as ajuste,
       hojas.num(datos -> 'Total')                           as total,
       hojas.num(datos -> 'VU (dias)')                       as vida_util_dias,
       hojas.fecha(datos -> 'Fecha limite de Entrega')       as fecha_limite_entrega,
       hojas.num(datos -> 'Dias Faltantes')                  as dias_faltantes,
       hojas.num(datos -> 'Política')                        as politica
from hojas.tabla
where fuente in ('stock_hf_cd', 'stock_hf_planta')
  and coalesce(hojas.num(datos -> 'CODIGO'), 0) > 0;

revoke all on core.ajustes_stock, core.stock_hf from anon, authenticated;

-- 4. Reportes.
-- 4a. Ajustes con kg y valor (costo por kg del mes; si el mes no tiene, el ultimo anterior).
create or replace view public.reporte_ajustes_stock as
select a.fecha,
       date_trunc('month', a.fecha)::date as mes,
       a.ajuste, a.motivo, a.quien, a.tipo, a.deposito,
       a.producto_codigo,
       coalesce(prd.producto, a.producto) as producto,
       coalesce(prd.familia, 'SIN CLASIFICAR') as familia,
       a.vencimiento,
       a.cantidad_signo                                   as cantidad,
       round(a.cantidad_signo * prd.kg_por, 2)            as kilos,
       round(a.cantidad_signo * prd.kg_por * c.costo_kg, 2) as valor_costo,
       case when a.motivo in ('Regalo', 'Muestra', 'Influencer', 'Consumo interno') then 'Uso comercial / interno'
            when a.motivo in ('Decomiso', 'Rotura') then 'Pérdida'
            when a.motivo ilike 'Diferencia de inventario%' then 'Diferencia de inventario'
            when a.motivo ilike 'Error Identificacion%' then 'Corrección de carga'
            when a.motivo ilike 'Re armado%' or a.motivo ilike 'Unificacion%' then 'Rearmado / cambio de formato'
            when a.motivo ilike 'Devolucion%' then 'Devolución'
            when a.motivo = 'Carga Inicial' then 'Carga inicial'
            else 'Otro' end                                as grupo_motivo,
       a.observacion
from core.ajustes_stock a
left join core.productos prd on prd.codigo = a.producto_codigo::text
left join lateral (
  select ca.costo_kg from core.costos_articulos ca
  where ca.articulo_codigo = lpad(a.producto_codigo::text, 7, '0') and ca.mes <= date_trunc('month', a.fecha)
  order by ca.mes desc limit 1
) c on true
where a.fecha is not null;

-- 4b. Stock disponible por lote.
create or replace view public.reporte_stock_hf as
select s.deposito, s.producto_codigo,
       coalesce(prd.producto, s.producto) as producto,
       coalesce(prd.familia, 'SIN CLASIFICAR') as familia,
       s.vencimiento, s.total as cantidad,
       round(s.total * prd.kg_por, 2) as kilos,
       s.ingreso, s.egreso, s.ajuste,
       s.fecha_limite_entrega,
       s.fecha_limite_entrega - current_date as dias_para_entregar,
       case when s.fecha_limite_entrega is null then 'Sin fecha'
            when s.fecha_limite_entrega < current_date then 'Pasó la fecha límite'
            when s.fecha_limite_entrega < current_date + 15 then 'Menos de 15 días'
            when s.fecha_limite_entrega < current_date + 30 then '15 a 30 días'
            else 'OK' end as estado_entrega,
       s.politica
from core.stock_hf s
left join core.productos prd on prd.codigo = s.producto_codigo::text
where s.total <> 0;

revoke all on public.reporte_ajustes_stock, public.reporte_stock_hf from anon, authenticated, public;
grant select on public.reporte_ajustes_stock, public.reporte_stock_hf to looker_lectura;

-- 5. Leer ahora y controlar (la lectura tarda unos minutos: si da 0, volver a correr este bloque).
select hojas.disparar();

select f.fuente as que,
       coalesce(f.ultimo_error, 'ok') || ' · ' || (select count(*) from hojas.filas h where h.fuente = f.fuente) || ' filas' as valor
from hojas.fuentes f where f.fuente in ('ajustes_stock', 'stock_hf_cd', 'stock_hf_planta')
union all select 'ajustes leidos', count(*)::text || ' renglones, ' || count(distinct ajuste) || ' ajustes' from core.ajustes_stock
union all select * from (
  select 'ajustes ' || to_char(mes, 'YYYY-MM') || ' · ' || grupo_motivo, round(sum(kilos))::text || ' kg'
  from public.reporte_ajustes_stock where mes >= date_trunc('month', current_date) - interval '2 months'
  group by mes, grupo_motivo order by mes, grupo_motivo) x
union all select 'stock disponible ' || deposito, round(sum(kilos))::text || ' kg' from public.reporte_stock_hf group by deposito;
