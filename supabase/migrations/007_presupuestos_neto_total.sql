-- 007_presupuestos_neto_total.sql
-- Validacion contra Tekno (26/10/2026, Auditoria de Ventas, P2 septiembre 2026): Tekno suma el TOTAL
-- de los presupuestos como neto. El P2 0003-00001037 (BIO SALUD) tenia IVA cargado ($62.858,18) y
-- Supabase daba $6.414.178,20 contra $6.477.036,38 de Tekno. Regla nueva: en P2 y Q2 (no fiscales)
-- neto = total. Las lineas del reporte se ajustan para sumar ese total. Facturas sin cambios.

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
  case when b.cc in ('P2','Q2') then abs(core.num(b.datos->>'IMPOVENT')) else abs(core.num(b.datos->>'NETOVENT')) end as neto,
  abs(core.num(b.datos->>'NGRAVENT'))                    as neto_gravado,
  abs(core.num(b.datos->>'IMPUVENT'))                    as iva,
  abs(core.num(b.datos->>'IMPOVENT'))                    as total,
  case when b.cc in ('P2','Q2') then abs(core.num(b.datos->>'IMPOVENT')) else abs(core.num(b.datos->>'NETOVENT')) end * case
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


create or replace view calc.ventas_analisis as
with cab as materialized (
  select v.orden, v.fecha, v.signo, v.tipo_comprobante, v.es_fiscal, v.neto,
         v.punto_venta, v.numero, v.cliente_codigo, v.vendedor_codigo
  from core.ventas_vigentes v
  where v.cuenta_como_venta
), det as materialized (
  select d.orden, d.articulo_codigo, d.es_despacho, d.cantidad, d.neto, d.neto_desbordado
  from core.ventas_detalle d
  where not d.eliminado_origen
), lineas as (
  select c.*, d.articulo_codigo, d.es_despacho,
         abs(d.cantidad) * c.signo as cantidad_linea,
         -- Presupuestos (no fiscales): las lineas se ajustan para sumar el total del comprobante,
         -- igual que el reporte de Tekno (caso P2 0003-00001037 con IVA cargado, 09/2026).
         abs(d.neto) * c.signo * case when c.es_fiscal then 1
           else coalesce(c.neto / nullif(sum(abs(d.neto)) over (partition by c.orden), 0), 1) end as neto_linea,
         d.neto_desbordado
  from cab c join det d on d.orden = c.orden
  union all
  select c.*, null, false, null, c.neto * c.signo, false
  from cab c
  where not exists (select 1 from det d where d.orden = c.orden)
), cli as materialized (
  select cl.codigo, cl.razon_social, cl.cuit, g.descripcion as grupo, g.tipo
  from core.clientes cl left join core.grupos_cliente g on g.codigo = cl.grupo_codigo
), art as materialized (
  select codigo, descripcion from core.articulos
), ven as materialized (
  select codigo, nombre from core.vendedores
)
select
  l.fecha,
  date_trunc('month', l.fecha)::date                          as mes,
  extract(year from l.fecha)::int                             as anio,
  case when l.es_fiscal then 'Factura' else 'Presupuesto' end as canal_fiscal,
  l.tipo_comprobante,
  lpad(l.punto_venta::text, 4, '0') || '-' || lpad(l.numero::text, 8, '0') as comprobante,
  l.cliente_codigo,
  coalesce(cli.razon_social, 'Cliente ' || l.cliente_codigo, 'Sin cliente') as cliente,
  cli.cuit                                                    as cliente_cuit,
  coalesce(cli.grupo, 'SIN GRUPO')                            as grupo_cliente,
  coalesce(cli.tipo, 'SIN GRUPO')                             as tipo_cliente,
  coalesce(ven.nombre, l.vendedor_codigo)                     as vendedor,
  coalesce(l.articulo_codigo, 'SIN DETALLE')                  as producto_codigo,
  case when l.articulo_codigo is null then 'SIN DETALLE'
       when l.es_despacho then 'DESPACHO (flete)'
       else coalesce(art.descripcion, l.articulo_codigo) end  as producto,
  l.es_despacho                                               as es_flete,
  l.cantidad_linea                                            as cantidad,
  l.neto_linea                                                as neto,
  l.neto_desbordado
from lineas l
left join cli on cli.codigo = l.cliente_codigo
left join art on art.codigo = l.articulo_codigo
left join ven on ven.codigo = l.vendedor_codigo;


-- Recalcular los reportes con la regla nueva.
select calc.refrescar_rpt();
