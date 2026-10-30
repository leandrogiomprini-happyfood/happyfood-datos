-- 032_cobranzas_neto_presupuestos.sql
-- Ajuste de la 031 (Cuci, 30/10/2026): un cobro sobre presupuesto no se divide por 1,21 (es neto).
-- Lo aplicado a un comprobante ya lo respetaba (neto/total del comprobante = 1 en presupuestos, incluso
-- en el P2 1037 de BIO SALUD con IVA mal cargado, por la regla de la 007). Lo que no: la parte
-- "a cuenta" y lo aplicado a comprobantes no identificados se dividian siempre por 1,21. Ahora usan la
-- proporcion neto/total de lo vendido a ESE cliente en los ultimos 12 meses (1 si compra solo con
-- presupuesto). Sin ventas en 12 meses: 1/1,21. Siguen marcados neto_estimado.
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

create or replace view calc.cobranzas_neto as
with rec as (
  select r.orden, r.numero, r.fecha, r.cliente_codigo, r.tipo_comprobante, r.importe
  from core.cobranzas r
  where r.fecha is not null
    and not exists (select 1 from core.clientes_internos i where i.codigo = r.cliente_codigo)
), apl as (
  select a.orden_recibo, a.orden_venta, a.monto
  from core.cobranzas_aplicaciones a
  where coalesce(a.monto, 0) <> 0
), ven as (
  select v.orden, v.tipo_comprobante, v.numero_completo, v.fecha, v.neto, v.total, v.es_fiscal,
         v.vendedor_codigo
  from core.ventas v
  where not v.eliminado_origen
), ratio as (
  -- proporcion neto/total de lo que se le vendio a cada cliente en los ultimos 12 meses:
  -- 1 si compra solo con presupuesto, ~0,83 si solo con factura, intermedio si mezcla
  select cliente_codigo, sum(neto) / nullif(sum(total), 0) as r
  from core.ventas
  where not eliminado_origen and cuenta_como_venta and signo = 1 and fecha >= current_date - 365
  group by cliente_codigo
), aplicado as (
  select rec.orden as orden_recibo, rec.numero, rec.fecha, rec.cliente_codigo,
         ven.tipo_comprobante as comprobante_tipo,
         ven.numero_completo as comprobante,
         ven.fecha as fecha_comprobante,
         case when ven.es_fiscal then 'Factura' when ven.orden is not null then 'Presupuesto' else 'Sin identificar' end as canal_fiscal,
         ven.vendedor_codigo,
         apl.monto as cobrado_total,
         apl.monto * case when ven.total > 0 then ven.neto / ven.total else coalesce(ra.r, 1 / 1.21) end as cobrado_neto,
         ven.orden is null as neto_estimado,
         false as a_cuenta
  from rec
  join apl on apl.orden_recibo = rec.orden
  left join ven on ven.orden = apl.orden_venta
  left join ratio ra on ra.cliente_codigo = rec.cliente_codigo
), a_cuenta as (
  select rec.orden, rec.numero, rec.fecha, rec.cliente_codigo,
         null::text, null::text, null::date, 'A cuenta', null::text,
         rec.importe - coalesce(sum(apl.monto), 0),
         (rec.importe - coalesce(sum(apl.monto), 0)) * coalesce(max(ra.r), 1 / 1.21),
         true, true
  from rec
  left join apl on apl.orden_recibo = rec.orden
  left join ratio ra on ra.cliente_codigo = rec.cliente_codigo
  group by rec.orden, rec.numero, rec.fecha, rec.cliente_codigo, rec.importe
  having abs(rec.importe - coalesce(sum(apl.monto), 0)) > 0.01
), todo as (
  select * from aplicado
  union all
  select * from a_cuenta
)
select t.fecha                                  as fecha_cobro,
       date_trunc('month', t.fecha)::date       as mes,
       t.numero                                 as recibo,
       t.cliente_codigo,
       coalesce(cl.razon_social, 'Cliente ' || t.cliente_codigo, 'Sin cliente') as cliente,
       coalesce(g.descripcion, 'SIN GRUPO')     as grupo_cliente,
       coalesce(g.tipo, 'SIN GRUPO')            as tipo_cliente,
       coalesce(vd.nombre, t.vendedor_codigo)   as vendedor,
       t.canal_fiscal,
       t.comprobante_tipo,
       t.comprobante,
       t.fecha_comprobante,
       t.fecha - t.fecha_comprobante            as dias_al_cobro,
       round(t.cobrado_total, 2)                as cobrado_total,
       round(t.cobrado_neto, 2)                 as cobrado_neto,
       round(t.cobrado_total - t.cobrado_neto, 2) as iva_cobrado,
       t.neto_estimado,
       t.a_cuenta
from todo t
left join core.clientes cl on cl.codigo = t.cliente_codigo
left join core.grupos_cliente g on g.codigo = cl.grupo_codigo
left join core.vendedores vd on vd.codigo = t.vendedor_codigo;

select calc.refrescar_rpt();

-- Control: BIO SALUD por mes (neto = con IVA si todo es presupuesto) y totales.
select to_char(mes, 'YYYY-MM') as mes, cliente,
       round(sum(cobrado_total), 2) as cobrado_con_iva, round(sum(cobrado_neto), 2) as cobrado_neto,
       bool_or(neto_estimado) as hay_estimado
from rpt.cobranzas_neto
where cliente ilike '%bio salud%' and mes >= '2026-07-01'
group by 1, 2 order by 1;
