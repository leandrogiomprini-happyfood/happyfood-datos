-- 004_rpt_tableros.sql
-- Vistas de reporte (esquema rpt) para Looker Studio y consultas con IA, y un usuario de solo lectura.
-- Solo crea vistas y permisos: no modifica datos. Se puede volver a ejecutar sin riesgo.
-- Requiere 001, 002 y 003.
--
-- Los tableros leen SOLO de rpt. Si cambia algo por dentro (core, tekno), rpt mantiene sus columnas.
-- Fechas de "hoy" en hora de Cordoba.

create schema if not exists rpt;

create or replace function rpt.hoy()
returns date
language sql
stable
as $$ select (now() at time zone 'America/Argentina/Cordoba')::date $$;

-- ---------------------------------------------------------------- Ventas
-- Un renglon por comprobante que cuenta como venta (facturas, NC, ND, presupuestos y sus NC).
create or replace view rpt.ventas_comprobantes as
select
  v.fecha,
  date_trunc('month', v.fecha)::date                 as mes,
  v.tipo_comprobante,
  v.clase,
  case when v.es_fiscal then 'Factura' else 'Presupuesto' end as canal_fiscal,
  lpad(v.punto_venta::text, 4, '0') || '-' || lpad(v.numero::text, 8, '0') as comprobante,
  v.cliente_codigo,
  coalesce(c.razon_social, 'Cliente ' || v.cliente_codigo, 'Sin cliente') as cliente,
  c.cuit                                             as cliente_cuit,
  coalesce(vd.nombre, v.vendedor_codigo)             as vendedor,
  coalesce(l.descripcion, v.lista_codigo)            as lista_precio,
  v.neto_con_signo                                   as neto,
  v.total_con_signo                                  as total,
  v.saldo_pendiente,
  v.orden
from core.ventas_vigentes v
left join core.clientes c       on c.codigo = v.cliente_codigo
left join core.vendedores vd    on vd.codigo = v.vendedor_codigo
left join core.listas_precio l  on l.codigo = v.lista_codigo
where v.cuenta_como_venta;

-- Un renglon por linea de producto (sin flete). Cantidad e importe con el signo del comprobante.
create or replace view rpt.ventas_lineas as
select
  v.fecha,
  v.mes,
  v.canal_fiscal,
  v.clase,
  v.comprobante,
  v.cliente,
  v.vendedor,
  d.articulo_codigo,
  coalesce(a.descripcion, d.articulo_codigo)         as articulo,
  abs(d.cantidad) * case when v.clase in ('nota_credito','nc_presupuesto') then -1 else 1 end as cantidad,
  abs(d.neto)     * case when v.clase in ('nota_credito','nc_presupuesto') then -1 else 1 end as neto,
  d.neto_desbordado
from core.ventas_detalle d
join rpt.ventas_comprobantes v on v.orden = d.orden
left join core.articulos a      on a.codigo = d.articulo_codigo
where not d.eliminado_origen
  and not d.es_despacho;

-- ---------------------------------------------------------------- Cobranzas
create or replace view rpt.cobranzas_recibos as
select
  r.fecha,
  date_trunc('month', r.fecha)::date                 as mes,
  r.numero,
  r.cliente_codigo,
  coalesce(c.razon_social, 'Cliente ' || r.cliente_codigo, 'Sin cliente') as cliente,
  r.importe
from core.cobranzas r
left join core.clientes c on c.codigo = r.cliente_codigo;

-- Deuda de clientes por cuota, con antiguedad respecto de hoy.
create or replace view rpt.cobranzas_pendientes as
select
  v.cliente_codigo,
  coalesce(c.razon_social, 'Cliente ' || v.cliente_codigo, 'Sin cliente') as cliente,
  coalesce(vd.nombre, v.vendedor_codigo)             as vendedor,
  lpad(v.punto_venta::text, 4, '0') || '-' || lpad(v.numero::text, 8, '0') as comprobante,
  v.tipo_comprobante,
  v.fecha                                            as fecha_comprobante,
  coalesce(vc.fecha_vencimiento, v.fecha)            as fecha_vencimiento,
  coalesce(vc.saldo, v.saldo_pendiente)              as saldo,
  rpt.hoy() - coalesce(vc.fecha_vencimiento, v.fecha) as dias_vencido,
  case
    when rpt.hoy() - coalesce(vc.fecha_vencimiento, v.fecha) <= 0  then '0 · A vencer'
    when rpt.hoy() - coalesce(vc.fecha_vencimiento, v.fecha) <= 30 then '1 · 1 a 30 dias'
    when rpt.hoy() - coalesce(vc.fecha_vencimiento, v.fecha) <= 60 then '2 · 31 a 60 dias'
    when rpt.hoy() - coalesce(vc.fecha_vencimiento, v.fecha) <= 90 then '3 · 61 a 90 dias'
    else '4 · Mas de 90 dias'
  end                                                as tramo
from core.ventas_vigentes v
left join core.ventas_vencimientos vc on vc.orden_venta = v.orden
left join core.clientes c             on c.codigo = v.cliente_codigo
left join core.vendedores vd          on vd.codigo = v.vendedor_codigo
where v.signo = 1
  and coalesce(vc.saldo, v.saldo_pendiente) > 0.009;

-- Dias reales de cobro de cada factura ya cancelada (fecha del ultimo recibo aplicado - fecha de la factura).
create or replace view rpt.dias_cobro as
select
  v.fecha                                            as fecha_comprobante,
  date_trunc('month', v.fecha)::date                 as mes,
  v.cliente_codigo,
  coalesce(c.razon_social, 'Cliente ' || v.cliente_codigo, 'Sin cliente') as cliente,
  lpad(v.punto_venta::text, 4, '0') || '-' || lpad(v.numero::text, 8, '0') as comprobante,
  v.total,
  max(r.fecha)                                       as fecha_ultimo_cobro,
  max(r.fecha) - v.fecha                             as dias_cobro
from core.ventas_vigentes v
join core.cobranzas_aplicaciones a on a.orden_venta = v.orden
join core.cobranzas r              on r.orden = a.orden_recibo
left join core.clientes c          on c.codigo = v.cliente_codigo
where v.signo = 1
  and coalesce(v.saldo_pendiente, 0) <= 0.009
group by v.orden, v.fecha, v.cliente_codigo, c.razon_social, v.punto_venta, v.numero, v.total;

-- ---------------------------------------------------------------- Compras y pagos
create or replace view rpt.compras as
select
  co.fecha,
  date_trunc('month', co.fecha)::date                as mes,
  co.tipo_comprobante,
  co.tipo_descripcion,
  co.clase,
  co.numero_proveedor                                as comprobante,
  co.proveedor_codigo,
  coalesce(p.razon_social, 'Proveedor ' || co.proveedor_codigo, 'Sin proveedor') as proveedor,
  coalesce(ru.descripcion, co.rubro_codigo)          as rubro,
  co.neto_con_signo                                  as neto,
  co.total_con_signo                                 as total,
  co.saldo_pendiente
from core.compras co
left join core.proveedores p on p.codigo = co.proveedor_codigo
left join core.rubros ru     on ru.codigo = co.rubro_codigo
where co.cuenta_como_compra;

-- Deuda con proveedores por cuota (incluye transferencias TF), con vencimiento respecto de hoy.
create or replace view rpt.deuda_proveedores as
select
  co.proveedor_codigo,
  coalesce(p.razon_social, 'Proveedor ' || co.proveedor_codigo, 'Sin proveedor') as proveedor,
  co.tipo_comprobante,
  co.numero_proveedor                                as comprobante,
  co.fecha                                           as fecha_comprobante,
  coalesce(vc.fecha_vencimiento, co.fecha)           as fecha_vencimiento,
  coalesce(vc.saldo, co.saldo_pendiente)             as saldo,
  coalesce(vc.fecha_vencimiento, co.fecha) - rpt.hoy() as dias_para_vencer,
  case
    when coalesce(vc.fecha_vencimiento, co.fecha) <  rpt.hoy()      then '0 · Vencido'
    when coalesce(vc.fecha_vencimiento, co.fecha) <= rpt.hoy() + 7  then '1 · Vence en 7 dias'
    when coalesce(vc.fecha_vencimiento, co.fecha) <= rpt.hoy() + 30 then '2 · Vence en 8 a 30 dias'
    else '3 · Vence en mas de 30 dias'
  end                                                as tramo
from core.compras co
left join core.compras_vencimientos vc on vc.orden_compra = co.orden
left join core.proveedores p           on p.codigo = co.proveedor_codigo
where co.signo = 1
  and coalesce(vc.saldo, co.saldo_pendiente) > 0.009;

create or replace view rpt.pagos as
select
  pa.fecha,
  date_trunc('month', pa.fecha)::date                as mes,
  pa.tipo_comprobante,
  pa.numero,
  pa.proveedor_codigo,
  coalesce(p.razon_social, 'Proveedor ' || pa.proveedor_codigo, 'Sin proveedor') as proveedor,
  pa.importe
from core.pagos pa
left join core.proveedores p on p.codigo = pa.proveedor_codigo;

-- ---------------------------------------------------------------- Frescura de los datos
-- Para mostrar en cada tablero cuando se actualizo cada fuente por ultima vez.
create or replace view rpt.estado_datos as
select 'ventas' as fuente, max(fecha_sincronizacion) at time zone 'America/Argentina/Cordoba' as ultima_actualizacion
from tekno.ventas
union all
select tabla, max(fecha_sincronizacion) at time zone 'America/Argentina/Cordoba'
from tekno.registros
group by tabla;

-- ---------------------------------------------------------------- Usuario de solo lectura
-- Se crea SIN clave y sin poder entrar. La clave la pone Cuci en Supabase con:
--   alter role looker_lectura with login password 'UNA_CLAVE_LARGA';
-- (nunca guardar la clave en este repositorio)
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'looker_lectura') then
    create role looker_lectura nologin;
  end if;
end $$;

grant usage on schema rpt to looker_lectura;
grant select on all tables in schema rpt to looker_lectura;
grant execute on function rpt.hoy() to looker_lectura;
alter default privileges in schema rpt grant select on tables to looker_lectura;
revoke all on schema tekno, core from looker_lectura;
