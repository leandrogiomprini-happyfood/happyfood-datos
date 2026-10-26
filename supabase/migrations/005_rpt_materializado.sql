-- 005_rpt_materializado.sql
-- Problema (26/10/2026): las vistas de rpt calculaban todo desde el JSON de Tekno en cada consulta.
-- "SELECT * FROM rpt.ventas_analisis LIMIT 100" tardo 15,8 s; Looker Studio se quedaba esperando.
-- Solucion: la logica pasa al esquema calc; rpt pasa a tener VISTAS MATERIALIZADAS (resultado
-- guardado) que se recalculan cada 10 minutos con pg_cron. Looker lee tablas ya calculadas.
-- Despues de esta migracion NO volver a ejecutar 004.

create schema if not exists calc;

-- 1. Mover la logica de rpt a calc (se conservan las definiciones de 004).
do $$
declare v text;
begin
  foreach v in array array['ventas_comprobantes','cobranzas_recibos','cobranzas_pendientes',
                           'dias_cobro','compras','deuda_proveedores','pagos'] loop
    if exists (select 1 from pg_views where schemaname = 'rpt' and viewname = v) then
      execute format('alter view rpt.%I set schema calc', v);
    end if;
  end loop;
  if exists (select 1 from pg_views where schemaname = 'rpt' and viewname = 'ventas_analisis') then
    execute 'drop view rpt.ventas_analisis';
  end if;
end $$;

-- 2. ventas_analisis reescrita: cada tabla se lee una sola vez (antes recorria el detalle por cada factura).
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
         abs(d.neto)     * c.signo as neto_linea,
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

-- 3. Vistas materializadas en rpt (lo que lee Looker). Mismos nombres y columnas que antes.
create materialized view if not exists rpt.ventas_analisis      as select * from calc.ventas_analisis      with no data;
create materialized view if not exists rpt.ventas_comprobantes  as select * from calc.ventas_comprobantes  with no data;
create materialized view if not exists rpt.cobranzas_recibos    as select * from calc.cobranzas_recibos    with no data;
create materialized view if not exists rpt.cobranzas_pendientes as select * from calc.cobranzas_pendientes with no data;
create materialized view if not exists rpt.dias_cobro           as select * from calc.dias_cobro           with no data;
create materialized view if not exists rpt.compras              as select * from calc.compras              with no data;
create materialized view if not exists rpt.deuda_proveedores    as select * from calc.deuda_proveedores    with no data;
create materialized view if not exists rpt.pagos                as select * from calc.pagos                with no data;

create index if not exists ventas_analisis_mes_idx     on rpt.ventas_analisis (mes);
create index if not exists ventas_analisis_cliente_idx on rpt.ventas_analisis (cliente_codigo);

-- 4. Recalculo. Se desactiva el plan "nested loop" solo durante el recalculo: con los datos en JSON
--    la base estima mal la cantidad de filas y elige un camino muy lento.
create table if not exists rpt.ultimo_recalculo (
  id          int primary key default 1 check (id = 1),
  fecha       timestamp not null,
  duracion_s  numeric not null
);

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
  insert into rpt.ultimo_recalculo (id, fecha, duracion_s)
  values (1, now() at time zone 'America/Argentina/Cordoba', extract(epoch from clock_timestamp() - t0))
  on conflict (id) do update set fecha = excluded.fecha, duracion_s = excluded.duracion_s;
end $$;

revoke all on function calc.refrescar_rpt() from public, anon, authenticated;

-- Primer calculo ahora.
select calc.refrescar_rpt();

-- 5. Recalculo automatico cada 10 minutos (pg_cron).
create extension if not exists pg_cron;
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'refrescar_rpt';
  perform cron.schedule('refrescar_rpt', '*/10 * * * *', 'select calc.refrescar_rpt()');
end $$;

-- 6. Permisos: Looker solo ve rpt.
revoke all on schema calc from looker_lectura;
grant usage on schema rpt to looker_lectura;
grant select on all tables in schema rpt to looker_lectura;
