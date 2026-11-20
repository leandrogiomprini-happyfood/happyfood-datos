-- 060_pedidos_entregas_pablo.sql
-- Cuci (20/11/2026): en el informe de Pablo mostrar pedidos, items no entregados por pedido y kilos y
-- montos pedidos, entregados y no entregados. SIN IVA y sin costos.
-- Fuente: planilla de Pedidos (core.pedidos + core.pedidos_detalle), todos los estados desde 01/01/2026.
--   pedido      = Cant. Solicitada
--   entregado   = Cant. Preparada (pedidos Cerrada, Parcial, Cerrada_F, Parcial_F)
--   no entregado= pedido - entregado, solo en pedidos ya cerrados o parciales
--   pendiente   = pedidos en estado "Pendiente" (todavia no se preparan: no cuentan como no entregados)
-- Precio sin IVA igual que en pedidos pendientes (057/059): ultimo precio del cliente por ese producto,
-- si no promedio 60 dias, si no promedio 12 meses. Es un monto estimado, no lo facturado.
-- Resultado guardado en rpt.pedidos_lineas y recalculado cada 10 minutos junto con los pendientes.
-- Vistas: public.reporte_pedidos_lineas (todos) y public.pablo_pedidos (solo su cartera, sin costos).
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

create or replace view calc.pedidos_lineas as
with ped as (
  select p.pedido, p.fecha, p.entrega_prevista, p.estado, p.cliente
  from core.pedidos p
  where p.fecha >= date '2026-01-01'
), lin as (
  select ped.*, d.producto_codigo, d.producto,
         coalesce(d.solicitado, 0) as solicitado,
         coalesce(d.preparado, 0)  as preparado
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
), x as (
  select l.*, pc.cliente_codigo,
         coalesce(prd.producto, l.producto) as producto_nombre,
         coalesce(prd.familia, 'SIN CLASIFICAR') as familia,
         prd.kg_por,
         l.estado = 'Pendiente' as pendiente,
         case when nf.cliente_pedido is not null then 0
              else coalesce(p1.precio, p2.precio, p3.precio) end as precio
  from lin l
  left join calc.pedidos_cliente pc on pc.cliente = l.cliente
  left join core.pedidos_no_facturables nf on upper(btrim(nf.cliente_pedido)) = upper(btrim(l.cliente))
  left join core.productos prd on prd.codigo = l.producto_codigo::text
  left join p1 on p1.cliente_codigo = pc.cliente_codigo and p1.producto_codigo = l.producto_codigo::text
  left join p2 on p2.producto_codigo = l.producto_codigo::text
  left join p3 on p3.producto_codigo = l.producto_codigo::text
)
select pedido, fecha, date_trunc('month', fecha)::date as mes, entrega_prevista, estado,
       case when pendiente then 'Pendiente' else 'Preparado' end as situacion,
       cliente, cliente_codigo, producto_codigo, producto_nombre as producto, familia,
       solicitado                                                        as cantidad_pedida,
       case when pendiente then 0 else preparado end                     as cantidad_entregada,
       case when pendiente then 0 else greatest(solicitado - preparado, 0) end as cantidad_no_entregada,
       case when pendiente then solicitado else 0 end                    as cantidad_pendiente,
       round(solicitado * kg_por, 2)                                     as kilos_pedidos,
       round(case when pendiente then 0 else preparado end * kg_por, 2)  as kilos_entregados,
       round(case when pendiente then 0 else greatest(solicitado - preparado, 0) end * kg_por, 2) as kilos_no_entregados,
       round(case when pendiente then solicitado else 0 end * kg_por, 2) as kilos_pendientes,
       round(solicitado * precio, 2)                                     as monto_pedido,
       round(case when pendiente then 0 else preparado end * precio, 2)  as monto_entregado,
       round(case when pendiente then 0 else greatest(solicitado - preparado, 0) end * precio, 2) as monto_no_entregado,
       round(case when pendiente then solicitado else 0 end * precio, 2) as monto_pendiente,
       case when not pendiente and preparado < solicitado then 1 else 0 end as item_no_entregado
from x;

drop view if exists public.pablo_pedidos;
drop view if exists public.reporte_pedidos_lineas;
drop materialized view if exists rpt.pedidos_lineas;
create materialized view rpt.pedidos_lineas as select * from calc.pedidos_lineas;
revoke all on rpt.pedidos_lineas from anon, authenticated;

create or replace view public.reporte_pedidos_lineas as select * from rpt.pedidos_lineas;

create or replace view public.pablo_pedidos as
select l.*
from rpt.pedidos_lineas l
join calc.cartera_vendedor c on c.portal = 'pablo' and c.cliente_codigo = l.cliente_codigo;

revoke all on public.reporte_pedidos_lineas, public.pablo_pedidos from anon, authenticated, public;
grant select on public.reporte_pedidos_lineas, public.pablo_pedidos to looker_lectura;
grant select on public.pablo_pedidos to looker_pablo;

-- Recalculo: pendientes (059) y lineas, cada 10 minutos.
create or replace function calc.refrescar_pedidos()
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  refresh materialized view rpt.pedidos_pendientes;
  refresh materialized view rpt.pedidos_lineas;
end $$;
revoke all on function calc.refrescar_pedidos() from public, anon, authenticated;

-- Control: Pablo por mes.
select to_char(mes, 'YYYY-MM') as mes,
       count(distinct pedido)            as pedidos,
       sum(item_no_entregado)            as items_no_entregados,
       round(sum(kilos_pedidos))         as kg_pedidos,
       round(sum(kilos_entregados))      as kg_entregados,
       round(sum(kilos_no_entregados))   as kg_no_entregados,
       round(sum(kilos_pendientes))      as kg_pendientes,
       round(sum(monto_pedido))          as monto_pedido,
       round(sum(monto_entregado))       as monto_entregado,
       round(sum(monto_no_entregado))    as monto_no_entregado
from public.pablo_pedidos
group by mes order by mes;
