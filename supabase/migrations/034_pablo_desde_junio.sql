-- 034_pablo_desde_junio.sql
-- Cuci (31/10/2026): el informe de Pablo muestra ventas, cobranzas e indicadores desde el 01/06/2026.
-- La fecha se guarda en core.portal_vendedores.desde y se aplica en la base (no en Looker), asi no
-- se puede sacar desde el informe. La deuda pendiente (pablo_deuda) se muestra completa: es lo que
-- sus clientes deben hoy, aunque la factura sea anterior a junio.
-- Para cambiar la fecha: update core.portal_vendedores set desde = 'AAAA-MM-DD' where portal = 'pablo';
-- Se puede volver a ejecutar sin riesgo.

alter table core.portal_vendedores add column if not exists desde date;
update core.portal_vendedores set desde = '2026-06-01' where portal = 'pablo';

create or replace view public.pablo_ventas as
select v.fecha, v.mes, v.anio, v.canal_fiscal, v.tipo_comprobante, v.comprobante,
       v.cliente_codigo, v.cliente, v.grupo_cliente, v.tipo_cliente,
       v.producto_codigo, v.producto, v.familia, v.es_flete,
       v.cantidad, v.unidades, v.kilos, v.neto
from rpt.ventas_analisis v
join calc.cartera_vendedor c on c.portal = 'pablo' and c.cliente_codigo = v.cliente_codigo
where v.fecha >= (select coalesce(min(desde), '2000-01-01') from core.portal_vendedores where portal = 'pablo');

create or replace view public.pablo_cobranzas as
select k.fecha_cobro, k.mes, k.recibo, k.cliente_codigo, k.cliente, k.tipo_cliente, k.canal_fiscal,
       k.comprobante_tipo, k.comprobante, k.fecha_comprobante, k.dias_al_cobro,
       k.cobrado_total, k.cobrado_neto, k.a_cuenta
from rpt.cobranzas_neto k
join calc.cartera_vendedor c on c.portal = 'pablo' and c.cliente_codigo = k.cliente_codigo
where k.fecha_cobro >= (select coalesce(min(desde), '2000-01-01') from core.portal_vendedores where portal = 'pablo');

create or replace view public.pablo_deuda as
select d.cliente_codigo, d.cliente, d.comprobante, d.tipo_comprobante, d.fecha_comprobante,
       d.fecha_vencimiento, d.saldo, d.dias_vencido, d.tramo
from rpt.cobranzas_pendientes d
join calc.cartera_vendedor c on c.portal = 'pablo' and c.cliente_codigo = d.cliente_codigo;

-- Un renglon por cliente: ultima compra y comparacion de los ultimos 90 dias contra los 90 anteriores.
create or replace view public.pablo_clientes as
select c.cliente_codigo,
       coalesce(cl.razon_social, 'Cliente ' || c.cliente_codigo) as cliente,
       coalesce(g.tipo, 'SIN GRUPO')                             as tipo_cliente,
       max(v.fecha)                                              as ultima_compra,
       current_date - max(v.fecha)                               as dias_sin_comprar,
       round(sum(v.neto) filter (where v.fecha > current_date - 90), 0)  as neto_ultimos_90,
       round(sum(v.neto) filter (where v.fecha <= current_date - 90 and v.fecha > current_date - 180), 0) as neto_90_anteriores,
       round(sum(v.kilos) filter (where v.fecha > current_date - 90), 0) as kilos_ultimos_90,
       count(distinct v.comprobante) filter (where v.fecha > current_date - 90) as compras_ultimos_90
from calc.cartera_vendedor c
left join rpt.ventas_analisis v on v.cliente_codigo = c.cliente_codigo
  and v.fecha >= (select coalesce(min(desde), '2000-01-01') from core.portal_vendedores where portal = 'pablo')
left join core.clientes cl on cl.codigo = c.cliente_codigo
left join core.grupos_cliente g on g.codigo = cl.grupo_codigo
where c.portal = 'pablo'
group by c.cliente_codigo, cl.razon_social, g.tipo;

-- Control: primer y ultimo mes que ve Pablo.
select 'ventas desde' as que, min(fecha)::text as valor from public.pablo_ventas
union all select 'cobranzas desde', min(fecha_cobro)::text from public.pablo_cobranzas
union all select 'clientes en la cartera', count(*)::text from public.pablo_clientes;
