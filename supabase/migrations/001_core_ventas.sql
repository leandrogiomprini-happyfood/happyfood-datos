-- 001_core_ventas.sql
-- Capa tipada (esquema core) sobre la copia cruda de Tekno (esquema tekno).
-- Solo crea un esquema, una funcion y vistas: no modifica ni borra datos de tekno.*.
-- Se puede volver a ejecutar sin riesgo (CREATE OR REPLACE).
--
-- Confirmado por Cuci el 24/10/2026:
--   CODICOMP: F1 factura contado / consumidor final, F2 factura, F7 factura de credito
--   electronica, P2 presupuesto (venta sin factura), A1 ajuste de credito, A2 ajuste de
--   debito, D2 nota de debito, Q2 nota de credito de presupuesto, C1/C2/C7 nota de credito.
--   Importes (factura 0003-00002526): NETOVENT = neto, NGRAVENT = neto gravado,
--   IMPUVENT = IVA, IMPOVENT = total, SALDVENT = saldo pendiente.
-- Sin confirmar (1 comprobante cada uno): F3, F8, C5, A3, A4, I2 -> clase 'otro', signo 0.
-- Los importes se guardan en positivo y el signo lo pone la clase (abs() * signo).

create schema if not exists core;

-- Convierte texto de Tekno a numero. Devuelve NULL si viene vacio o desbordado ('*****').
create or replace function core.num(t text)
returns numeric
language sql
immutable
as $$
  select case
           when t is null then null
           when btrim(t) ~ '^-?[0-9]+(\.[0-9]+)?$' then btrim(t)::numeric
           else null
         end
$$;

-- Convierte texto a fecha. Devuelve NULL si viene vacio o con formato inesperado.
create or replace function core.fecha(t text)
returns date
language sql
immutable
as $$
  select case
           when btrim(coalesce(t, '')) ~ '^\d{4}-\d{2}-\d{2}$' then btrim(t)::date
           else null
         end
$$;

create or replace view core.ventas as
with base as (
  select v.*, btrim(v.datos->>'CODICOMP') as cc
  from tekno.ventas v
)
select
  b.registro_origen,
  core.num(b.datos->>'ORDEVENT')::bigint                 as orden,
  b.cc                                                   as tipo_comprobante,
  case
    when b.cc in ('F1','F2','F7')      then 'factura'
    when b.cc in ('C1','C2','C7')      then 'nota_credito'
    when b.cc = 'D2'                   then 'nota_debito'
    when b.cc = 'P2'                   then 'presupuesto'
    when b.cc = 'Q2'                   then 'nc_presupuesto'
    when b.cc = 'A1'                   then 'ajuste_credito'
    when b.cc = 'A2'                   then 'ajuste_debito'
    else 'otro'
  end                                                    as clase,
  case
    when b.cc in ('F1','F2','F7','D2','P2','A2') then 1
    when b.cc in ('C1','C2','C7','Q2','A1')      then -1
    else 0
  end                                                    as signo,
  b.cc in ('F1','F2','F7','C1','C2','C7','D2')           as es_fiscal,
  b.cc in ('F1','F2','F7','C1','C2','C7','D2','P2','Q2') as cuenta_como_venta,
  nullif(btrim(b.datos->>'TIPOVENT'), '')                as letra,
  core.num(left(btrim(b.datos->>'NUMEVENT'), 4))::int    as punto_venta,
  core.num(right(btrim(b.datos->>'NUMEVENT'), 8))::bigint as numero,
  btrim(b.datos->>'NUMEVENT')                            as numero_completo,
  core.fecha(b.datos->>'FECHVENT')                       as fecha,
  core.fecha(b.datos->>'FECHACARGA')                     as fecha_carga,
  nullif(btrim(b.datos->>'CODICLIE'), '')                as cliente_codigo,
  nullif(btrim(b.datos->>'CODIVEND'), '')                as vendedor_codigo,
  nullif(btrim(b.datos->>'CODILIST'), '')                as lista_codigo,
  nullif(btrim(b.datos->>'CODIFOPA'), '')                as forma_pago_codigo,
  nullif(btrim(b.datos->>'CODISIFI'), '')                as condicion_fiscal,
  nullif(btrim(b.datos->>'REMIVENT'), '')                as remito,
  abs(core.num(b.datos->>'NETOVENT'))                    as neto,
  abs(core.num(b.datos->>'NGRAVENT'))                    as neto_gravado,
  abs(core.num(b.datos->>'IMPUVENT'))                    as iva,
  abs(core.num(b.datos->>'IMPOVENT'))                    as total,
  abs(core.num(b.datos->>'NETOVENT')) * case
    when b.cc in ('F1','F2','F7','D2','P2','A2') then 1
    when b.cc in ('C1','C2','C7','Q2','A1')      then -1
    else 0 end                                           as neto_con_signo,
  abs(core.num(b.datos->>'IMPOVENT')) * case
    when b.cc in ('F1','F2','F7','D2','P2','A2') then 1
    when b.cc in ('C1','C2','C7','Q2','A1')      then -1
    else 0 end                                           as total_con_signo,
  core.num(b.datos->>'SALDVENT')                         as saldo_pendiente,
  nullif(btrim(b.datos->>'NUMECAE'), '')                 as cae,
  core.fecha(b.datos->>'FECHANUL') is not null           as anulado,
  b.eliminado_origen,
  b.fecha_sincronizacion
from base b;

create or replace view core.ventas_detalle as
select
  d.registro_origen,
  core.num(d.datos->>'ORDEFINA')::bigint   as linea,
  core.num(d.datos->>'ORDECOMP')::bigint   as orden,          -- une con core.ventas.orden
  nullif(btrim(d.datos->>'CODIARTI'), '')  as articulo_codigo,
  btrim(d.datos->>'CODIARTI') = '1111111'  as es_despacho,    -- linea de flete, no es producto
  core.fecha(d.datos->>'FECHFINA')         as fecha,
  core.num(d.datos->>'CANTFINA')           as cantidad,
  core.num(d.datos->>'PRECLIST')           as precio_lista,
  core.num(d.datos->>'BONIFINA')           as bonificacion_pct,
  core.num(d.datos->>'NETOFINA')           as neto,
  (d.datos->>'NETOFINA') like '%*%'        as neto_desbordado, -- el DBF no pudo mostrar el numero
  core.num(d.datos->>'IMP1FINA')           as impuesto_1,
  nullif(btrim(d.datos->>'CODIIMP1'), '')  as impuesto_1_codigo,
  core.num(d.datos->>'COSTFINA')           as costo,
  d.eliminado_origen,
  d.fecha_sincronizacion
from tekno.ventas_detalle d;

-- Ventas vigentes: sin eliminados ni anulados. Es la base de los tableros.
create or replace view core.ventas_vigentes as
select *
from core.ventas
where not eliminado_origen
  and not anulado;

comment on view core.ventas is 'Comprobantes de venta de Tekno tipados. Borrador: confirmar CODICOMP e importes.';
comment on view core.ventas_detalle is 'Lineas de comprobantes de Tekno tipadas. orden une con core.ventas.orden.';
