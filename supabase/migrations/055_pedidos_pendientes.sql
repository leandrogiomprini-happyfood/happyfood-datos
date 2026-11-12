-- 055_pedidos_pendientes.sql
-- Pedidos pendientes por cliente con el monto estimado a facturar, SIN IVA (pedido de Cuci, 12/11/2026).
-- Fuente: planilla de Pedidos (core.pedidos y core.pedidos_detalle, 014). Pendiente = Estado "Pendiente".
-- "Valor Declarado" de la planilla NO se usa (es otra cosa).
-- Precio de cada linea (neto sin IVA por unidad del codigo, de las ventas de Tekno):
--   1. ultimo precio que pago ESE cliente por ESE producto en los ultimos 180 dias;
--   2. si no: precio promedio del producto en los ultimos 60 dias (todos los clientes);
--   3. si no: precio promedio del producto en los ultimos 365 dias.
--   Cada linea dice de donde salio el precio (origen_precio).
-- El cliente del pedido es texto: se empareja con Tekno por razon social; lo que no empareja se carga a
-- mano en core.pedidos_cliente_map (insert into core.pedidos_cliente_map values ('<nombre en pedidos>', '<codigo Tekno>');).
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- 1. Emparejar el cliente del pedido con Tekno.
create table if not exists core.pedidos_cliente_map (
  cliente_pedido  text primary key,
  cliente_codigo  text not null
);
alter table core.pedidos_cliente_map enable row level security;
revoke all on core.pedidos_cliente_map from anon, authenticated;

create or replace view calc.pedidos_cliente as
with nombres as (
  select distinct cliente from core.pedidos where cliente is not null
  union
  select distinct cliente from core.pedidos_detalle where cliente is not null
), norm as (
  select cliente, upper(regexp_replace(btrim(cliente), '\s+', ' ', 'g')) as n from nombres
), cli as (
  select codigo, upper(regexp_replace(btrim(razon_social), '\s+', ' ', 'g')) as n from core.clientes
)
select x.cliente,
       coalesce(m.cliente_codigo,
                (select c.codigo from cli c where c.n = x.n limit 1),
                (select c.codigo from cli c where c.n like x.n || '%' or x.n like c.n || '%'
                 order by length(c.n) limit 1)) as cliente_codigo,
       case when m.cliente_codigo is not null then 'manual'
            when exists (select 1 from cli c where c.n = x.n) then 'exacto'
            when exists (select 1 from cli c where c.n like x.n || '%' or x.n like c.n || '%') then 'parecido'
            else 'sin emparejar' end as emparejado
from norm x
left join core.pedidos_cliente_map m on m.cliente_pedido = x.cliente;

-- 2. Precios de venta (neto sin IVA por unidad del codigo).
create or replace view calc.precios_venta as
select cliente_codigo, ltrim(producto_codigo, '0') as producto_codigo, fecha, neto / cantidad as precio
from rpt.ventas_analisis
where producto_codigo ~ '^[0-9]+$' and cantidad > 0 and neto / cantidad >= 1
  and fecha >= current_date - 365;

-- 3. Lineas pendientes con precio estimado.
create or replace view calc.pedidos_pendientes as
with ped as (
  select p.pedido, p.fecha, p.entrega_prevista, p.cliente, p.orden_compra, p.tipo_cliente, p.lista_precio,
         p.tipo_facturacion
  from core.pedidos p
  where p.estado = 'Pendiente'
), lin as (
  select ped.*, d.linea, d.producto_codigo, d.producto, coalesce(d.solicitado, 0) as cantidad
  from ped join core.pedidos_detalle d on d.pedido = ped.pedido
  where coalesce(d.solicitado, 0) > 0
)
select l.pedido, l.fecha, l.entrega_prevista, l.cliente, pc.cliente_codigo, pc.emparejado,
       l.orden_compra, l.tipo_cliente, l.lista_precio, l.tipo_facturacion,
       l.linea, l.producto_codigo, coalesce(prd.producto, l.producto) as producto,
       coalesce(prd.familia, 'SIN CLASIFICAR') as familia,
       l.cantidad,
       round(l.cantidad * prd.kg_por, 2) as kilos,
       round(coalesce(p1.precio, p2.precio, p3.precio), 2) as precio_unitario,
       case when p1.precio is not null then 'último del cliente'
            when p2.precio is not null then 'promedio 60 días'
            when p3.precio is not null then 'promedio 12 meses'
            else 'sin precio' end as origen_precio,
       round(l.cantidad * coalesce(p1.precio, p2.precio, p3.precio), 2) as monto_estimado
from lin l
left join calc.pedidos_cliente pc on pc.cliente = l.cliente
left join core.productos prd on prd.codigo = l.producto_codigo::text
left join lateral (
  select v.precio from calc.precios_venta v
  where v.cliente_codigo = pc.cliente_codigo and v.producto_codigo = l.producto_codigo::text
    and v.fecha >= current_date - 180
  order by v.fecha desc limit 1
) p1 on true
left join lateral (
  select avg(v.precio) as precio from calc.precios_venta v
  where v.producto_codigo = l.producto_codigo::text and v.fecha >= current_date - 60
) p2 on true
left join lateral (
  select avg(v.precio) as precio from calc.precios_venta v
  where v.producto_codigo = l.producto_codigo::text
) p3 on true;

-- 4. Reportes para Looker (sin IVA).
create or replace view public.reporte_pedidos_pendientes as
select pedido, fecha, entrega_prevista, current_date - fecha as dias_desde_pedido,
       cliente, cliente_codigo, emparejado, orden_compra, tipo_cliente,
       producto_codigo, producto, familia, cantidad, kilos,
       precio_unitario, origen_precio, monto_estimado
from calc.pedidos_pendientes;

create or replace view public.reporte_pedidos_pendientes_cliente as
select cliente, cliente_codigo,
       count(distinct pedido)           as pedidos,
       min(fecha)                       as pedido_mas_viejo,
       min(entrega_prevista)            as proxima_entrega,
       round(sum(cantidad))             as cantidad,
       round(sum(kilos))                as kilos,
       round(sum(monto_estimado))       as monto_estimado,
       count(*) filter (where origen_precio <> 'último del cliente') as lineas_con_precio_promedio,
       count(*) filter (where origen_precio = 'sin precio')          as lineas_sin_precio
from calc.pedidos_pendientes
group by cliente, cliente_codigo;

revoke all on calc.pedidos_cliente, calc.precios_venta, calc.pedidos_pendientes from anon, authenticated;
revoke all on public.reporte_pedidos_pendientes, public.reporte_pedidos_pendientes_cliente
  from anon, authenticated, public;
grant select on public.reporte_pedidos_pendientes, public.reporte_pedidos_pendientes_cliente to looker_lectura;

-- 5. Control.
select 'TOTAL' as cliente, null as codigo, sum(pedidos)::text as pedidos, sum(kilos)::text as kilos,
       sum(monto_estimado)::text as monto_sin_iva, sum(lineas_con_precio_promedio)::text as lineas_precio_promedio,
       sum(lineas_sin_precio)::text as lineas_sin_precio
from public.reporte_pedidos_pendientes_cliente
union all
select cliente, coalesce(cliente_codigo, 'SIN EMPAREJAR'), pedidos::text, kilos::text, monto_estimado::text,
       lineas_con_precio_promedio::text, lineas_sin_precio::text
from (select * from public.reporte_pedidos_pendientes_cliente order by monto_estimado desc nulls last) x;
