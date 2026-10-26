-- 006_reportes_en_public.sql
-- El conector PostgreSQL de Looker Studio solo lista tablas del esquema public
-- (https://docs.cloud.google.com/looker/docs/studio/connect-to-postgresql).
-- Se crean vistas public.reporte_* que leen las tablas ya calculadas de rpt.
-- Supabase publica public por su API: se quitan los permisos de anon y authenticated para que
-- estos datos NO queden expuestos; solo looker_lectura puede leerlos.

create or replace view public.reporte_ventas          as select * from rpt.ventas_analisis;
create or replace view public.reporte_comprobantes    as select * from rpt.ventas_comprobantes;
create or replace view public.reporte_cobranzas       as select * from rpt.cobranzas_recibos;
create or replace view public.reporte_deuda_clientes  as select * from rpt.cobranzas_pendientes;
create or replace view public.reporte_dias_cobro      as select * from rpt.dias_cobro;
create or replace view public.reporte_compras         as select * from rpt.compras;
create or replace view public.reporte_deuda_proveedores as select * from rpt.deuda_proveedores;
create or replace view public.reporte_pagos           as select * from rpt.pagos;
create or replace view public.reporte_estado_datos    as
  select fuente, ultima_actualizacion from rpt.estado_datos
  union all
  select 'reportes', fecha from rpt.ultimo_recalculo;

revoke all on public.reporte_ventas, public.reporte_comprobantes, public.reporte_cobranzas,
  public.reporte_deuda_clientes, public.reporte_dias_cobro, public.reporte_compras,
  public.reporte_deuda_proveedores, public.reporte_pagos, public.reporte_estado_datos
  from anon, authenticated, public;

grant usage on schema public to looker_lectura;
grant select on public.reporte_ventas, public.reporte_comprobantes, public.reporte_cobranzas,
  public.reporte_deuda_clientes, public.reporte_dias_cobro, public.reporte_compras,
  public.reporte_deuda_proveedores, public.reporte_pagos, public.reporte_estado_datos
  to looker_lectura;
