-- 001_core_ventas.sql
-- Capa tipada (esquema core) sobre la copia cruda de Tekno (esquema tekno).
-- Solo crea un esquema, una funcion y vistas: no modifica ni borra datos de tekno.*.
-- Se puede volver a ejecutar sin riesgo (CREATE OR REPLACE).
--
-- PENDIENTE DE CONFIRMAR (ver docs/diccionario_tekno_ventas.md):
--   * significado de cada CODICOMP (F2, F7, C2, C7, P2, A1, Q2, D2, ...)
--   * cual de NETOVENT / NGRAVENT / IMPOVENT es neto sin IVA y cual total
-- Hasta confirmarlo, signo y clase se derivan solo de la primera letra:
--   F = factura (+1), D = nota de debito (+1), C = nota de credito (-1),
--   P = presupuesto (+1, no fiscal), resto = 'otro' (0, se excluye de la venta).

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
select
  v.registro_origen,
  core.num(v.datos->>'ORDEVENT')::bigint                 as orden,
  btrim(v.datos->>'CODICOMP')                            as tipo_comprobante,
  left(btrim(v.datos->>'CODICOMP'), 1)                   as clase,
  case left(btrim(v.datos->>'CODICOMP'), 1)
    when 'F' then 'factura'
    when 'C' then 'nota_credito'
    when 'D' then 'nota_debito'
    when 'P' then 'presupuesto'
    else 'otro'
  end                                                    as clase_nombre,
  case left(btrim(v.datos->>'CODICOMP'), 1)
    when 'F' then 1 when 'D' then 1 when 'P' then 1
    when 'C' then -1
    else 0
  end                                                    as signo,
  left(btrim(v.datos->>'CODICOMP'), 1) in ('F','C','D')  as es_fiscal,
  nullif(btrim(v.datos->>'TIPOVENT'), '')                as letra,
  core.num(left(btrim(v.datos->>'NUMEVENT'), 4))::int    as punto_venta,
  core.num(right(btrim(v.datos->>'NUMEVENT'), 8))::bigint as numero,
  btrim(v.datos->>'NUMEVENT')                            as numero_completo,
  core.fecha(v.datos->>'FECHVENT')                       as fecha,
  core.fecha(v.datos->>'FECHACARGA')                     as fecha_carga,
  nullif(btrim(v.datos->>'CODICLIE'), '')                as cliente_codigo,
  nullif(btrim(v.datos->>'CODIVEND'), '')                as vendedor_codigo,
  nullif(btrim(v.datos->>'CODILIST'), '')                as lista_codigo,
  nullif(btrim(v.datos->>'CODIFOPA'), '')                as forma_pago_codigo,
  nullif(btrim(v.datos->>'CODISIFI'), '')                as condicion_fiscal,
  nullif(btrim(v.datos->>'REMIVENT'), '')                as remito,
  core.num(v.datos->>'NETOVENT')                         as importe_netovent,
  core.num(v.datos->>'NGRAVENT')                         as importe_ngravent,
  core.num(v.datos->>'IMPUVENT')                         as importe_impuestos,
  core.num(v.datos->>'IMPOVENT')                         as importe_impovent,
  core.num(v.datos->>'SALDVENT')                         as saldo_pendiente,
  nullif(btrim(v.datos->>'NUMECAE'), '')                 as cae,
  core.fecha(v.datos->>'FECHANUL') is not null           as anulado,
  v.eliminado_origen,
  v.fecha_sincronizacion
from tekno.ventas v;

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
