-- 028_costos_contribucion.sql
-- Costo de lo vendido y contribucion marginal en el reporte de ventas (pedido de Cuci, 30/10/2026).
-- Fuente: planilla movivent, hoja kgxArtiActual (leida desde la 027): columna A codigo, D kilos por
-- bulto, y una columna de COSTO POR KILO por mes con encabezado "2026 - 8", "2026 -9", etc. (fila 1).
--   costo        = kilos vendidos x costo por kilo del mes de la venta
--   contribucion = neto - costo
-- Cada costo rige desde su mes hasta el mes del siguiente costo cargado. Ventas anteriores al primer
-- costo cargado de un articulo usan ese primer costo y quedan marcadas costo_estimado = true.
-- Notas de credito sin detalle (descuentos) y fletes: contribucion = su neto (no tienen costo de producto).
-- Kilos: los del maestro de productos (010); si el codigo no esta en el maestro, los de la columna D.
-- Columnas nuevas al final del reporte: costo_kg, costo, contribucion, costo_mes, costo_estimado.
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

create or replace view core.costos_articulos as
with meses as (
  select (x.ord - 1)::int as idx, m[1]::int as anio, m[2]::int as mes
  from hojas.filas f
  cross join lateral jsonb_array_elements(f.valores) with ordinality as x(v, ord)
  cross join lateral regexp_match(btrim(x.v #>> '{}'), '^(\d{4})\s*-\s*(\d{1,2})$') as m
  where f.fuente = 'costos_articulos' and f.fila = 1 and m is not null
)
select lpad(hojas.num(r.valores -> 0)::bigint::text, 7, '0') as articulo_codigo,
       hojas.txt(r.valores -> 2)                            as descripcion,
       hojas.num(r.valores -> 3)                            as kg_por_bulto,
       make_date(me.anio, me.mes, 1)                        as mes,
       hojas.num(r.valores -> me.idx)                       as costo_kg
from hojas.filas r
join meses me on me.mes between 1 and 12
where r.fuente = 'costos_articulos' and r.fila > 1
  and hojas.num(r.valores -> 0) is not null
  and hojas.num(r.valores -> me.idx) > 0;

revoke all on core.costos_articulos from anon, authenticated;

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
         -- Presupuestos (no fiscales): las lineas se ajustan para sumar el total del comprobante (007).
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
), prd as materialized (
  select codigo_tekno, familia, unidades_por, kg_por, estado from core.productos
), cst as materialized (
  -- costo por kilo de cada articulo y mes (planilla movivent, hoja kgxArtiActual); cada costo rige
  -- desde su mes hasta el siguiente costo cargado
  select articulo_codigo, mes, costo_kg, kg_por_bulto,
         lead(mes) over (partition by articulo_codigo order by mes) as hasta,
         min(mes) over (partition by articulo_codigo) as primero
  from core.costos_articulos
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
  l.neto_desbordado,
  case when l.articulo_codigo is null then 'SIN DETALLE'
       when l.es_despacho then 'DESPACHO'
       else coalesce(prd.familia, 'SIN CLASIFICAR') end      as familia,
  l.cantidad_linea * prd.unidades_por                         as unidades,
  round(l.cantidad_linea * coalesce(prd.kg_por, cst.kg_por_bulto), 3) as kilos,
  prd.estado                                                  as producto_estado,
  cst.costo_kg,
  round(l.cantidad_linea * coalesce(prd.kg_por, cst.kg_por_bulto) * cst.costo_kg, 2) as costo,
  -- notas de credito sin detalle (descuentos) y fletes no tienen costo de producto: contribuyen su neto
  case when l.articulo_codigo is null or l.es_despacho then l.neto_linea
       else round(l.neto_linea - l.cantidad_linea * coalesce(prd.kg_por, cst.kg_por_bulto) * cst.costo_kg, 2)
  end                                                         as contribucion,
  cst.mes                                                     as costo_mes,
  date_trunc('month', l.fecha)::date < cst.primero            as costo_estimado
from lineas l
left join cli on cli.codigo = l.cliente_codigo
left join art on art.codigo = l.articulo_codigo
left join ven on ven.codigo = l.vendedor_codigo
left join prd on prd.codigo_tekno = lpad(l.articulo_codigo, 7, '0')
left join cst on cst.articulo_codigo = lpad(l.articulo_codigo, 7, '0')
  and not l.es_despacho
  and ( (date_trunc('month', l.fecha)::date >= cst.mes
         and (cst.hasta is null or date_trunc('month', l.fecha)::date < cst.hasta))
     or (date_trunc('month', l.fecha)::date < cst.primero and cst.mes = cst.primero) );

-- La vista materializada y la vista de Looker se recrean para tomar las columnas nuevas.
drop view if exists public.reporte_ventas;
drop materialized view if exists rpt.ventas_analisis;
create materialized view rpt.ventas_analisis as select * from calc.ventas_analisis with no data;
create index if not exists ventas_analisis_mes_idx     on rpt.ventas_analisis (mes);
create index if not exists ventas_analisis_cliente_idx on rpt.ventas_analisis (cliente_codigo);

create or replace view public.reporte_ventas as select * from rpt.ventas_analisis;
revoke all on public.reporte_ventas from anon, authenticated, public;
grant select on rpt.ventas_analisis, public.reporte_ventas to looker_lectura;

select calc.refrescar_rpt();


-- Control: costo y contribucion por mes (ultimos 6 meses) y lineas sin costo.
select to_char(mes, 'YYYY-MM') as mes,
       round(sum(neto), 0)         as neto,
       round(sum(costo), 0)        as costo,
       round(sum(contribucion), 0) as contribucion,
       round(100 * sum(contribucion) / nullif(sum(neto) filter (where contribucion is not null), 0), 1) as margen_pct,
       round(100.0 * count(*) filter (where costo is null and not es_flete and producto_codigo <> 'SIN DETALLE')
             / nullif(count(*) filter (where not es_flete and producto_codigo <> 'SIN DETALLE'), 0), 1) as pct_lineas_sin_costo,
       bool_or(costo_estimado) as hay_costo_estimado
from rpt.ventas_analisis
where mes >= date_trunc('month', current_date) - interval '5 months'
group by mes
order by mes;
