-- 059_pedidos_pendientes_rapido.sql
-- Cuci (17/11/2026): en Looker la tabla de pedidos pendientes tardaba mucho y no cargaba. La vista
-- buscaba el precio linea por linea en un año de ventas cada vez que Looker pedia datos.
--   * calc.pedidos_pendientes: mismas columnas y mismo criterio de precio (057), pero los precios se
--     calculan una sola vez por cliente/producto y por producto.
--   * rpt.pedidos_pendientes: resultado guardado (vista materializada), recalculado cada 10 minutos.
--   * reporte_pedidos_pendientes y reporte_pedidos_pendientes_cliente leen el resultado guardado.
-- Looker no cambia (mismos campos). Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

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
), pv as materialized (
  select * from calc.precios_venta
  where producto_codigo in (select distinct producto_codigo::text from lin)
), p1 as (
  select distinct on (cliente_codigo, producto_codigo) cliente_codigo, producto_codigo, precio
  from pv where fecha >= current_date - 180
  order by cliente_codigo, producto_codigo, fecha desc
), p2 as (
  select producto_codigo, avg(precio) as precio from pv where fecha >= current_date - 60 group by 1
), p3 as (
  select producto_codigo, avg(precio) as precio from pv group by 1
)
select l.pedido, l.fecha, l.entrega_prevista, l.cliente, pc.cliente_codigo, pc.emparejado,
       l.orden_compra, l.tipo_cliente, l.lista_precio, l.tipo_facturacion,
       l.linea, l.producto_codigo, coalesce(prd.producto, l.producto) as producto,
       coalesce(prd.familia, 'SIN CLASIFICAR') as familia,
       l.cantidad,
       round(l.cantidad * prd.kg_por, 2) as kilos,
       case when nf.cliente_pedido is not null then 0
            else round(coalesce(p1.precio, p2.precio, p3.precio), 2) end as precio_unitario,
       case when nf.cliente_pedido is not null then 'no se factura'
            when p1.precio is not null then 'último del cliente'
            when p2.precio is not null then 'promedio 60 días'
            when p3.precio is not null then 'promedio 12 meses'
            else 'sin precio' end as origen_precio,
       case when nf.cliente_pedido is not null then 0
            else round(l.cantidad * coalesce(p1.precio, p2.precio, p3.precio), 2) end as monto_estimado
from lin l
left join calc.pedidos_cliente pc on pc.cliente = l.cliente
left join core.pedidos_no_facturables nf on upper(btrim(nf.cliente_pedido)) = upper(btrim(l.cliente))
left join core.productos prd on prd.codigo = l.producto_codigo::text
left join p1 on p1.cliente_codigo = pc.cliente_codigo and p1.producto_codigo = l.producto_codigo::text
left join p2 on p2.producto_codigo = l.producto_codigo::text
left join p3 on p3.producto_codigo = l.producto_codigo::text;

-- Resultado guardado.
drop view if exists public.reporte_pedidos_pendientes_cliente;
drop view if exists public.reporte_pedidos_pendientes;
drop materialized view if exists rpt.pedidos_pendientes;
create materialized view rpt.pedidos_pendientes as select * from calc.pedidos_pendientes;
revoke all on rpt.pedidos_pendientes from anon, authenticated;

create or replace view public.reporte_pedidos_pendientes as
select pedido, fecha, entrega_prevista, current_date - fecha as dias_desde_pedido,
       cliente, cliente_codigo, emparejado, orden_compra, tipo_cliente,
       producto_codigo, producto, familia, cantidad, kilos,
       precio_unitario, origen_precio, monto_estimado
from rpt.pedidos_pendientes;

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
from rpt.pedidos_pendientes
group by cliente, cliente_codigo;

revoke all on public.reporte_pedidos_pendientes, public.reporte_pedidos_pendientes_cliente
  from anon, authenticated, public;
grant select on public.reporte_pedidos_pendientes, public.reporte_pedidos_pendientes_cliente to looker_lectura;

-- Recalculo cada 10 minutos.
create or replace function calc.refrescar_pedidos()
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  refresh materialized view rpt.pedidos_pendientes;
end $$;
revoke all on function calc.refrescar_pedidos() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'refrescar_pedidos';
  perform cron.schedule('refrescar_pedidos', '*/10 * * * *', 'select calc.refrescar_pedidos()');
end $$;

-- Control.
select 'lineas pendientes' as que, count(*)::text as valor from rpt.pedidos_pendientes
union all select 'pedidos', count(distinct pedido)::text from rpt.pedidos_pendientes
union all select 'monto estimado sin IVA', round(sum(monto_estimado))::text from rpt.pedidos_pendientes;
