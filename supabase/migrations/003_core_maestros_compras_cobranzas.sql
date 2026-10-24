-- 003_core_maestros_compras_cobranzas.sql
-- Vistas tipadas (esquema core) sobre las tablas de Tekno que llegan a tekno.registros.
-- Solo crea vistas: no modifica datos. Se puede volver a ejecutar sin riesgo.
-- Requiere 001 (funciones core.num y core.fecha) y 002 (tekno.registros).
--
-- Signo de los comprobantes: sale de la propia tabla de Tekno (TABLCOMP):
--   TIPOCOMP = circuito (V ventas, C compras, O cobranzas, P pagos)
--   STIPCOMP = D debito / C credito
--   Compras: credito (factura) suma deuda con el proveedor = +1; debito (nota de credito) = -1.
-- Pendiente de confirmar: TF (transferencia bancaria, 932 comprobantes) se cuenta en la cuenta
-- corriente del proveedor pero NO como compra/gasto (cuenta_como_compra = false).

-- Registros vigentes de una tabla de Tekno (sin los borrados en origen).
create or replace view core.tekno_vigentes as
select tabla, registro_origen, datos, fecha_sincronizacion
from tekno.registros
where not eliminado_origen;

-- ---------------------------------------------------------------- Tipos de comprobante
create or replace view core.tipos_comprobante as
select distinct on (btrim(datos->>'CODICOMP'))
  btrim(datos->>'CODICOMP')                     as codigo,
  nullif(btrim(datos->>'DESCCOMP'), '')         as descripcion,
  nullif(btrim(datos->>'TIPOCOMP'), '')         as circuito,
  case btrim(datos->>'TIPOCOMP')
    when 'V' then 'ventas' when 'C' then 'compras' when 'O' then 'cobranzas'
    when 'P' then 'pagos'  when 'B' then 'bancos'  when 'J' then 'caja'
    when 'S' then 'stock'  else 'otro' end      as circuito_nombre,
  nullif(btrim(datos->>'STIPCOMP'), '')         as subtipo,
  nullif(btrim(datos->>'CODIAFIP_A'), '')       as codigo_afip_a,
  nullif(btrim(datos->>'CODIAFIP_B'), '')       as codigo_afip_b
from core.tekno_vigentes
where tabla = 'tablcomp' and btrim(datos->>'CODICOMP') <> ''
order by btrim(datos->>'CODICOMP'), (nullif(btrim(datos->>'DESCCOMP'), '') is null), registro_origen;

-- ---------------------------------------------------------------- Maestros
create or replace view core.clientes as
select
  btrim(datos->>'CODICLIE')                                   as codigo,
  btrim(datos->>'RASOCLIE')                                   as razon_social,
  nullif(regexp_replace(datos->>'CUITCLIE', '\D', '', 'g'), '') as cuit,
  nullif(btrim(datos->>'CODISIFI'), '')                       as condicion_fiscal,
  nullif(btrim(datos->>'CODIVEND'), '')                       as vendedor_codigo,
  nullif(btrim(datos->>'CODILIST'), '')                       as lista_codigo,
  nullif(btrim(datos->>'CODIZONA'), '')                       as zona_codigo,
  nullif(btrim(datos->>'CODIGRCL'), '')                       as grupo_codigo,
  nullif(btrim(datos->>'DIRECLIE'), '')                       as direccion,
  nullif(btrim(datos->>'CPOSCLIE'), '')                       as codigo_postal,
  nullif(btrim(datos->>'TELECLIE'), '')                       as telefono,
  nullif(btrim(datos->>'MAILCLIE'), '')                       as email,
  core.num(datos->>'SADOCLIE')                                as saldo_tekno,
  core.fecha(datos->>'FEALCLIE')                              as fecha_alta,
  registro_origen
from core.tekno_vigentes
where tabla = 'maesclie';

create or replace view core.proveedores as
select
  btrim(datos->>'CODIPROV')                                   as codigo,
  btrim(datos->>'RASOPROV')                                   as razon_social,
  nullif(regexp_replace(datos->>'CUITPROV', '\D', '', 'g'), '') as cuit,
  nullif(btrim(datos->>'CODIRUBR'), '')                       as rubro_codigo,
  nullif(btrim(datos->>'CODISIFI'), '')                       as condicion_fiscal,
  nullif(btrim(datos->>'MAILPROV'), '')                       as email,
  nullif(btrim(datos->>'TELEPROV'), '')                       as telefono,
  nullif(btrim(datos->>'CONTPROV'), '')                       as contacto,
  core.num(datos->>'SALDPROV')                                as saldo_tekno,
  core.fecha(datos->>'FEALPROV')                              as fecha_alta,
  registro_origen
from core.tekno_vigentes
where tabla = 'maesprov';

create or replace view core.articulos as
select
  btrim(datos->>'CODIARTI')                  as codigo,
  btrim(datos->>'DESCARTI')                  as descripcion,
  btrim(datos->>'CODIARTI') = '1111111'      as es_despacho,
  nullif(btrim(datos->>'UNMEARTI'), '')      as unidad,
  nullif(btrim(datos->>'CODIGRAR'), '')      as grupo_codigo,
  core.num(datos->>'PRECARTI')               as precio_tekno,
  nullif(btrim(datos->>'OBSOARTI'), '')      as obsoleto,
  core.fecha(datos->>'ULMOARTI')             as ultimo_movimiento,
  registro_origen
from core.tekno_vigentes
where tabla = 'maesarti';

create or replace view core.precios as
select
  btrim(datos->>'GRARARTI')                  as articulo_codigo,
  btrim(datos->>'CODILIST')                  as lista_codigo,
  core.num(datos->>'ACTUPREC')               as precio_actual,
  core.num(datos->>'ANTEPREC')               as precio_anterior,
  core.fecha(datos->>'FEACPREC')             as fecha_precio_actual,
  core.fecha(datos->>'FEANPREC')             as fecha_precio_anterior,
  registro_origen
from core.tekno_vigentes
where tabla = 'maesprec';

create or replace view core.vendedores as
select btrim(datos->>'CODIVEND') as codigo, btrim(datos->>'NOMBVEND') as nombre
from core.tekno_vigentes where tabla = 'tablvend';

create or replace view core.listas_precio as
select btrim(datos->>'CODILIST') as codigo, btrim(datos->>'DESCLIST') as descripcion
from core.tekno_vigentes where tabla = 'tabllist';

create or replace view core.rubros as
select btrim(datos->>'CODIRUBR') as codigo, btrim(datos->>'DESCRUBR') as descripcion
from core.tekno_vigentes where tabla = 'tablrubr';

create or replace view core.formas_pago as
select btrim(datos->>'CODIFOPA') as codigo, btrim(datos->>'DESCFOPA') as descripcion
from core.tekno_vigentes where tabla = 'tablfopa';

create or replace view core.plan_cuentas as
select btrim(datos->>'NUMECUEN') as cuenta, btrim(datos->>'DESCCUEN') as descripcion,
       core.num(datos->>'NIVECUEN')::int as nivel
from core.tekno_vigentes where tabla = 'maescuen';

-- ---------------------------------------------------------------- Ventas: vencimientos
create or replace view core.ventas_vencimientos as
select
  core.num(datos->>'ORDEVENT')::bigint       as orden_venta,
  core.num(datos->>'ORDEVENC')::bigint       as cuota,
  core.fecha(datos->>'FECHVENC')             as fecha_vencimiento,
  core.num(datos->>'IMPOVENC')               as importe,
  core.num(datos->>'SALDVENC')               as saldo
from core.tekno_vigentes
where tabla = 'auxivenc';

-- ---------------------------------------------------------------- Cobranzas
create or replace view core.cobranzas as
select
  core.num(c.datos->>'ORDECOBR')::bigint          as orden,
  btrim(c.datos->>'CODICOMP')                     as tipo_comprobante,
  t.descripcion                                   as tipo_descripcion,
  btrim(c.datos->>'NUMECOBR')                     as numero,
  core.fecha(c.datos->>'FECHCOBR')                as fecha,
  core.fecha(c.datos->>'FECHREAL')                as fecha_real,
  nullif(btrim(c.datos->>'CODICLIE'), '')         as cliente_codigo,
  core.num(c.datos->>'IMPOCOBR')                  as importe,
  core.num(c.datos->>'DESCCOBR')                  as descuento,
  core.num(c.datos->>'RECACOBR')                  as recargo,
  core.num(c.datos->>'SALDCOBR')                  as saldo_sin_aplicar,
  c.registro_origen
from core.tekno_vigentes c
left join core.tipos_comprobante t on t.codigo = btrim(c.datos->>'CODICOMP')
where c.tabla = 'movicobr';

create or replace view core.cobranzas_medios as
select
  core.num(datos->>'ORDEPAGO')::bigint       as orden_recibo,
  core.num(datos->>'ORDECONC')::bigint       as linea,
  nullif(btrim(datos->>'CODIFOPA'), '')      as forma_pago_codigo,
  nullif(btrim(datos->>'NUMECONC'), '')      as numero_valor,
  core.num(datos->>'IMPOCONC')               as importe,
  core.fecha(datos->>'FECHCONC')             as fecha
from core.tekno_vigentes
where tabla = 'detacobr';

-- Que recibo cancelo que factura, y por cuanto.
create or replace view core.cobranzas_aplicaciones as
select
  core.num(datos->>'ORDEVENT')::bigint       as orden_venta,
  core.num(datos->>'ORDECOBR')::bigint       as orden_recibo,
  core.num(datos->>'MONTAPLI')               as monto,
  core.num(datos->>'BONIAPLI')               as bonificacion,
  core.fecha(datos->>'FEVEAPLI')             as fecha_vencimiento
from core.tekno_vigentes
where tabla = 'auxiapli';

-- ---------------------------------------------------------------- Compras y gastos
create or replace view core.compras as
with base as (
  select c.*, btrim(c.datos->>'CODICOMP') as cc, t.descripcion, t.subtipo
  from core.tekno_vigentes c
  left join core.tipos_comprobante t on t.codigo = btrim(c.datos->>'CODICOMP')
  where c.tabla = 'movicomp'
)
select
  core.num(datos->>'ORDECOMP')::bigint            as orden,
  cc                                              as tipo_comprobante,
  descripcion                                     as tipo_descripcion,
  case left(cc, 1)
    when 'F' then 'factura' when 'C' then 'nota_credito' when 'D' then 'nota_debito'
    when 'A' then 'ajuste'  when 'T' then 'transferencia' when 'R' then 'retencion'
    when 'I' then 'retencion' else 'otro' end     as clase,
  case subtipo when 'C' then 1 when 'D' then -1 else 0 end as signo,
  left(cc, 1) in ('F','C','D')                    as cuenta_como_compra,
  btrim(datos->>'NUMECOMP')                       as numero_interno,
  nullif(btrim(datos->>'NUPRCOMP'), '')           as numero_proveedor,
  core.fecha(datos->>'FECHCOMP')                  as fecha,
  core.fecha(datos->>'FECHREAL')                  as fecha_real,
  nullif(btrim(datos->>'CODIPROV'), '')           as proveedor_codigo,
  nullif(btrim(datos->>'CODIRUBR'), '')           as rubro_codigo,
  nullif(btrim(datos->>'NUMECUEN'), '')           as cuenta,
  abs(core.num(datos->>'NETOCOMP'))               as neto,
  abs(core.num(datos->>'NGRACOMP'))               as neto_gravado,
  abs(core.num(datos->>'IMPUCOMP'))               as iva,
  abs(core.num(datos->>'IMPOCOMP'))               as total,
  abs(core.num(datos->>'NETOCOMP')) * case subtipo when 'C' then 1 when 'D' then -1 else 0 end as neto_con_signo,
  abs(core.num(datos->>'IMPOCOMP')) * case subtipo when 'C' then 1 when 'D' then -1 else 0 end as total_con_signo,
  core.num(datos->>'SALDCOMP')                    as saldo_pendiente,
  registro_origen
from base;

create or replace view core.compras_detalle as
select
  core.num(datos->>'ORDECOMP')::bigint       as orden,
  core.num(datos->>'ORDEFINA')::bigint       as linea,
  nullif(btrim(datos->>'CODIARTI'), '')      as articulo_codigo,
  core.fecha(datos->>'FECHFINA')             as fecha,
  core.num(datos->>'CANTFINA')               as cantidad,
  core.num(datos->>'NETOFINA')               as neto,
  core.num(datos->>'IMP1FINA')               as impuesto_1,
  nullif(btrim(datos->>'NUMECUEN'), '')      as cuenta
from core.tekno_vigentes
where tabla = 'detacomp';

create or replace view core.compras_vencimientos as
select
  core.num(datos->>'ORDECOMP')::bigint       as orden_compra,
  core.num(datos->>'ORDEVECO')::bigint       as cuota,
  core.fecha(datos->>'FECHVECO')             as fecha_vencimiento,
  core.num(datos->>'IMPOVECO')               as importe,
  core.num(datos->>'SALDVECO')               as saldo
from core.tekno_vigentes
where tabla = 'venccomp';

-- ---------------------------------------------------------------- Pagos
create or replace view core.pagos as
select
  core.num(p.datos->>'ORDEPAGO')::bigint          as orden,
  btrim(p.datos->>'CODICOMP')                     as tipo_comprobante,
  t.descripcion                                   as tipo_descripcion,
  btrim(p.datos->>'NUMEPAGO')                     as numero,
  core.fecha(p.datos->>'FECHPAGO')                as fecha,
  nullif(btrim(p.datos->>'CODIPROV'), '')         as proveedor_codigo,
  core.num(p.datos->>'IMPOPAGO')                  as importe,
  core.num(p.datos->>'SALDPAGO')                  as saldo_sin_aplicar,
  p.registro_origen
from core.tekno_vigentes p
left join core.tipos_comprobante t on t.codigo = btrim(p.datos->>'CODICOMP')
where p.tabla = 'movipago';

create or replace view core.pagos_medios as
select
  core.num(datos->>'ORDEPAGO')::bigint       as orden_pago,
  core.num(datos->>'ORDECONC')::bigint       as linea,
  nullif(btrim(datos->>'CODIFOPA'), '')      as forma_pago_codigo,
  nullif(btrim(datos->>'NUMECONC'), '')      as numero_valor,
  core.num(datos->>'IMPOCONC')               as importe,
  core.fecha(datos->>'FECHCONC')             as fecha
from core.tekno_vigentes
where tabla = 'detapago';

create or replace view core.pagos_aplicaciones as
select
  core.num(datos->>'ORDECOMP')::bigint       as orden_compra,
  core.num(datos->>'ORDEPAGO')::bigint       as orden_pago,
  core.num(datos->>'MONTAPPA')               as monto,
  core.fecha(datos->>'FEVEAPPA')             as fecha_vencimiento
from core.tekno_vigentes
where tabla = 'aplicomp';
