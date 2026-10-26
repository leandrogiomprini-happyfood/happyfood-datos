-- 004_rpt_tableros.sql
-- Vistas de reporte (esquema rpt) para Looker Studio y consultas con IA, y un usuario de solo lectura.
-- Solo crea vistas y permisos: no modifica datos. Se puede volver a ejecutar sin riesgo.
-- Requiere 001, 002 y 003.
--
-- Los tableros leen SOLO de rpt. Si cambia algo por dentro (core, tekno), rpt mantiene sus columnas.
-- Fechas de "hoy" en hora de Cordoba.

create schema if not exists rpt;

-- rpt solo tiene vistas (sin datos): se recrean de cero para poder cambiar columnas sin errores.
drop view if exists rpt.ventas_analisis, rpt.ventas_lineas, rpt.ventas_comprobantes,
  rpt.cobranzas_recibos, rpt.cobranzas_pendientes, rpt.dias_cobro, rpt.compras,
  rpt.deuda_proveedores, rpt.pagos, rpt.estado_datos cascade;

create or replace function rpt.hoy()
returns date
language sql
stable
as $$ select (now() at time zone 'America/Argentina/Cordoba')::date $$;

-- ---------------------------------------------------------------- Grupos de cliente
-- Fuente: MAESGRCL de Tekno (se suma al sincronizador). Mientras no llegue, se usan los nombres de abajo.
-- tipo = equivalencia con la planilla de pedidos (propuesta del 26/10/2026, a confirmar por Cuci).
insert into tekno.tablas_permitidas (tabla, archivo_dbf, descripcion)
values ('maesgrcl', 'MAESGRCL.DBF', 'Grupos de clientes')
on conflict (tabla) do nothing;

create or replace view core.grupos_cliente as
with tekno as (
  select btrim(datos->>'CODIGRCL') as codigo, nullif(btrim(datos->>'DESCGRCL'), '') as descripcion
  from core.tekno_vigentes where tabla = 'maesgrcl'
), codigos as (
  select codigo from tekno
  union
  select distinct grupo_codigo from core.clientes where grupo_codigo is not null
)
select
  k.codigo,
  coalesce(t.descripcion, case k.codigo
    when '01' then 'MAYORISTAS DIETETICA' when '02' then 'DISTRIBUIDORES DIETE'
    when '03' then 'MAYORISTAS TRADE'     when '04' then 'DISTRIBUIDORES TRADE'
    when '05' then 'SUPERMERCADOS'        when 'CO' then 'CLIENTES ON LINE'
    when 'IE' then 'IMPORTADOR/EXPORTADO' else k.codigo end) as descripcion,
  case
    when k.codigo in ('01','02','03','04') then 'DISTRI'
    when k.codigo = '05' then 'SUPER'
    when k.codigo = 'CO' then 'TIENDA'
    when k.codigo = 'IE' then 'EXPO'
    else 'SIN TIPO'
  end as tipo
from codigos k
left join tekno t on t.codigo = k.codigo;

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
  coalesce(g.descripcion, 'SIN GRUPO')               as grupo_cliente,
  coalesce(g.tipo, 'SIN GRUPO')                      as tipo_cliente,
  coalesce(vd.nombre, v.vendedor_codigo)             as vendedor,
  coalesce(l.descripcion, v.lista_codigo)            as lista_precio,
  v.neto_con_signo                                   as neto,
  v.total_con_signo                                  as total,
  v.saldo_pendiente,
  v.orden
from core.ventas_vigentes v
left join core.clientes c       on c.codigo = v.cliente_codigo
left join core.grupos_cliente g on g.codigo = c.grupo_codigo
left join core.vendedores vd    on vd.codigo = v.vendedor_codigo
left join core.listas_precio l  on l.codigo = v.lista_codigo
where v.cuenta_como_venta;

-- REPORTE PRINCIPAL: un renglon por linea de factura/presupuesto (DETAVENT).
-- Filas = cliente, columnas = mes, valor = neto. Filtros: periodo, cliente, grupo/tipo de cliente, producto.
-- La suma de las lineas da el neto de cada comprobante (validado el 26/10/2026 contra 15 comprobantes).
-- Tekno guarda el neto de la linea con el signo invertido; aca se usa abs() * signo del comprobante.
-- Comprobantes sin lineas aparecen con un renglon "SIN DETALLE" para que el total siempre cierre.
create or replace view rpt.ventas_analisis as
with cab as (
  select v.orden, v.fecha, v.signo, v.tipo_comprobante, v.clase, v.es_fiscal, v.neto,
         v.punto_venta, v.numero, v.cliente_codigo, v.vendedor_codigo
  from core.ventas_vigentes v
  where v.cuenta_como_venta
), lineas as (
  select c.orden, d.articulo_codigo, d.es_despacho,
         abs(d.cantidad) * c.signo as cantidad,
         abs(d.neto)     * c.signo as neto,
         d.neto_desbordado
  from cab c
  join core.ventas_detalle d on d.orden = c.orden and not d.eliminado_origen
  union all
  select c.orden, null, false, null, c.neto * c.signo, false
  from cab c
  where not exists (select 1 from core.ventas_detalle d where d.orden = c.orden and not d.eliminado_origen)
)
select
  c.fecha,
  date_trunc('month', c.fecha)::date                         as mes,
  extract(year from c.fecha)::int                            as anio,
  case when c.es_fiscal then 'Factura' else 'Presupuesto' end as canal_fiscal,
  c.tipo_comprobante,
  lpad(c.punto_venta::text, 4, '0') || '-' || lpad(c.numero::text, 8, '0') as comprobante,
  c.cliente_codigo,
  coalesce(cl.razon_social, 'Cliente ' || c.cliente_codigo, 'Sin cliente') as cliente,
  cl.cuit                                                    as cliente_cuit,
  coalesce(g.descripcion, 'SIN GRUPO')                       as grupo_cliente,
  coalesce(g.tipo, 'SIN GRUPO')                              as tipo_cliente,
  coalesce(vd.nombre, c.vendedor_codigo)                     as vendedor,
  coalesce(l.articulo_codigo, 'SIN DETALLE')                 as producto_codigo,
  case when l.articulo_codigo is null then 'SIN DETALLE'
       when l.es_despacho then 'DESPACHO (flete)'
       else coalesce(a.descripcion, l.articulo_codigo) end   as producto,
  l.es_despacho                                              as es_flete,
  l.cantidad,
  l.neto,
  l.neto_desbordado
from lineas l
join cab c                    on c.orden = l.orden
left join core.clientes cl    on cl.codigo = c.cliente_codigo
left join core.grupos_cliente g on g.codigo = cl.grupo_codigo
left join core.vendedores vd  on vd.codigo = c.vendedor_codigo
left join core.articulos a    on a.codigo = l.articulo_codigo;

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
grant select on all tables in schema rpt to looker_lectura;  -- vuelve a otorgar si se agregan vistas
grant execute on function rpt.hoy() to looker_lectura;
alter default privileges in schema rpt grant select on tables to looker_lectura;
revoke all on schema tekno, core from looker_lectura;
