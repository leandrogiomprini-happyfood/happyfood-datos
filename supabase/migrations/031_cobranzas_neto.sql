-- 031_cobranzas_neto.sql
-- Cobranzas en NETO SIN IVA (pedido de Cuci, 30/10/2026; hoy lo calcula a mano).
-- Un recibo cobra importes con IVA. Para pasarlo a neto se usa a que comprobantes se aplico
-- (AUXIAPLI de Tekno): cada importe aplicado se multiplica por neto / total de ESE comprobante.
--   factura A/B con IVA 21%  -> aplicado / 1,21
--   presupuesto (sin IVA)    -> aplicado tal cual
-- La parte de un recibo que no se aplico a ningun comprobante ("a cuenta") no tiene comprobante
-- para saber su IVA: se estima como importe / 1,21 y queda marcada neto_estimado = true.
-- Clientes internos (008/009) excluidos, igual que en ventas.
-- Resultado en rpt.cobranzas_neto (se recalcula con los demas reportes cada 10 min) y para Looker en
-- public.reporte_cobranzas_neto. Se puede volver a ejecutar sin riesgo.

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
), aplicado as (
  select rec.orden as orden_recibo, rec.numero, rec.fecha, rec.cliente_codigo,
         ven.tipo_comprobante as comprobante_tipo,
         ven.numero_completo as comprobante,
         ven.fecha as fecha_comprobante,
         case when ven.es_fiscal then 'Factura' when ven.orden is not null then 'Presupuesto' else 'Sin identificar' end as canal_fiscal,
         ven.vendedor_codigo,
         apl.monto as cobrado_total,
         apl.monto * case when ven.total > 0 then ven.neto / ven.total else 1 / 1.21 end as cobrado_neto,
         ven.orden is null as neto_estimado,
         false as a_cuenta
  from rec
  join apl on apl.orden_recibo = rec.orden
  left join ven on ven.orden = apl.orden_venta
), a_cuenta as (
  select rec.orden, rec.numero, rec.fecha, rec.cliente_codigo,
         null::text, null::text, null::date, 'A cuenta', null::text,
         rec.importe - coalesce(sum(apl.monto), 0),
         (rec.importe - coalesce(sum(apl.monto), 0)) / 1.21,
         true, true
  from rec
  left join apl on apl.orden_recibo = rec.orden
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

drop view if exists public.reporte_cobranzas_neto;
drop materialized view if exists rpt.cobranzas_neto;
create materialized view rpt.cobranzas_neto as select * from calc.cobranzas_neto with no data;
create index if not exists cobranzas_neto_mes_idx on rpt.cobranzas_neto (mes);

-- Se suma al recalculo de los reportes (cada 10 min).
create or replace function calc.refrescar_rpt()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare t0 timestamptz := clock_timestamp();
begin
  perform set_config('enable_nestloop', 'off', true);
  refresh materialized view rpt.ventas_analisis;
  refresh materialized view rpt.ventas_comprobantes;
  refresh materialized view rpt.cobranzas_recibos;
  refresh materialized view rpt.cobranzas_pendientes;
  refresh materialized view rpt.dias_cobro;
  refresh materialized view rpt.compras;
  refresh materialized view rpt.deuda_proveedores;
  refresh materialized view rpt.pagos;
  refresh materialized view rpt.cobranzas_neto;
  insert into rpt.ultimo_recalculo (id, fecha, duracion_s)
  values (1, now() at time zone 'America/Argentina/Cordoba', extract(epoch from clock_timestamp() - t0))
  on conflict (id) do update set fecha = excluded.fecha, duracion_s = excluded.duracion_s;
end $$;
revoke all on function calc.refrescar_rpt() from public, anon, authenticated;

select calc.refrescar_rpt();

create or replace view public.reporte_cobranzas_neto as select * from rpt.cobranzas_neto;
revoke all on public.reporte_cobranzas_neto from anon, authenticated, public;
grant select on rpt.cobranzas_neto, public.reporte_cobranzas_neto to looker_lectura;

-- Control: cobrado por mes (ultimos 4), total y neto, y cuanto es a cuenta (estimado).
select to_char(mes, 'YYYY-MM') as mes,
       round(sum(cobrado_total), 0) as cobrado_con_iva,
       round(sum(cobrado_neto), 0)  as cobrado_neto,
       round(sum(cobrado_neto) filter (where canal_fiscal = 'Factura'), 0)     as neto_facturas,
       round(sum(cobrado_neto) filter (where canal_fiscal = 'Presupuesto'), 0) as neto_presupuestos,
       round(sum(cobrado_total) filter (where a_cuenta), 0)                    as a_cuenta_con_iva,
       round(sum(cobrado_total) - (select sum(importe) from core.cobranzas r
                                   where date_trunc('month', r.fecha) = x.mes
                                     and not exists (select 1 from core.clientes_internos i where i.codigo = r.cliente_codigo)), 0)
         as diferencia_vs_recibos
from rpt.cobranzas_neto x
where mes >= date_trunc('month', current_date) - interval '3 months'
group by mes
order by mes;
