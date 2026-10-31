-- 033_informe_pablo.sql
-- Informe de Looker solo para Pablo (pedido de Cuci, 31/10/2026): ventas, cobranzas y mix de SUS
-- clientes, sin costos ni margen.
-- Seguridad: no alcanza con un filtro en Looker (quien edita el informe lo saca). Por eso:
--   * vistas propias (public.pablo_*) que ya traen SOLO sus clientes y sin columnas de costo;
--   * un usuario de base propio (looker_pablo) que solo puede leer esas vistas. El informe de Pablo
--     se conecta con ese usuario: aunque alguien cambie la tabla de la fuente, no ve nada mas.
-- Cartera: cliente cuyo ULTIMO comprobante de venta (ultimos 12 meses) tiene el vendedor de Pablo en
-- Tekno. Si un cliente pasa a otro vendedor, sale solo de la cartera.
-- El codigo de vendedor se carga en core.portal_vendedores (abajo se busca por nombre "PABLO").
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- 1. Que codigo de vendedor corresponde a cada informe.
create table if not exists core.portal_vendedores (
  portal          text not null,
  vendedor_codigo text not null,
  primary key (portal, vendedor_codigo)
);
alter table core.portal_vendedores enable row level security;
revoke all on core.portal_vendedores from anon, authenticated;

insert into core.portal_vendedores (portal, vendedor_codigo)
select 'pablo', codigo from core.vendedores where nombre ilike '%pablo%'
on conflict do nothing;

-- 2. Cartera.
create or replace view calc.cartera_vendedor as
with ult as (
  select distinct on (cliente_codigo) cliente_codigo, vendedor_codigo, fecha
  from core.ventas_vigentes
  where cuenta_como_venta and signo = 1 and fecha >= current_date - 365 and cliente_codigo is not null
  order by cliente_codigo, fecha desc, orden desc
)
select p.portal, u.cliente_codigo, u.vendedor_codigo, u.fecha as ultima_venta
from ult u
join core.portal_vendedores p on p.vendedor_codigo = u.vendedor_codigo;

-- 3. Vistas del informe (sin costo, contribucion ni margen).
create or replace view public.pablo_ventas as
select v.fecha, v.mes, v.anio, v.canal_fiscal, v.tipo_comprobante, v.comprobante,
       v.cliente_codigo, v.cliente, v.grupo_cliente, v.tipo_cliente,
       v.producto_codigo, v.producto, v.familia, v.es_flete,
       v.cantidad, v.unidades, v.kilos, v.neto
from rpt.ventas_analisis v
join calc.cartera_vendedor c on c.portal = 'pablo' and c.cliente_codigo = v.cliente_codigo;

create or replace view public.pablo_cobranzas as
select k.fecha_cobro, k.mes, k.recibo, k.cliente_codigo, k.cliente, k.tipo_cliente, k.canal_fiscal,
       k.comprobante_tipo, k.comprobante, k.fecha_comprobante, k.dias_al_cobro,
       k.cobrado_total, k.cobrado_neto, k.a_cuenta
from rpt.cobranzas_neto k
join calc.cartera_vendedor c on c.portal = 'pablo' and c.cliente_codigo = k.cliente_codigo;

create or replace view public.pablo_deuda as
select d.cliente_codigo, d.cliente, d.comprobante, d.tipo_comprobante, d.fecha_comprobante,
       d.fecha_vencimiento, d.saldo, d.dias_vencido, d.tramo
from rpt.cobranzas_pendientes d
join calc.cartera_vendedor c on c.portal = 'pablo' and c.cliente_codigo = d.cliente_codigo;

-- Un renglon por cliente: ultima compra y comparacion de los ultimos 90 dias contra los 90 anteriores.
create or replace view public.pablo_clientes as
select c.cliente_codigo,
       coalesce(cl.razon_social, 'Cliente ' || c.cliente_codigo) as cliente,
       coalesce(g.tipo, 'SIN GRUPO')                             as tipo_cliente,
       max(v.fecha)                                              as ultima_compra,
       current_date - max(v.fecha)                               as dias_sin_comprar,
       round(sum(v.neto) filter (where v.fecha > current_date - 90), 0)  as neto_ultimos_90,
       round(sum(v.neto) filter (where v.fecha <= current_date - 90 and v.fecha > current_date - 180), 0) as neto_90_anteriores,
       round(sum(v.kilos) filter (where v.fecha > current_date - 90), 0) as kilos_ultimos_90,
       count(distinct v.comprobante) filter (where v.fecha > current_date - 90) as compras_ultimos_90
from calc.cartera_vendedor c
left join rpt.ventas_analisis v on v.cliente_codigo = c.cliente_codigo
left join core.clientes cl on cl.codigo = c.cliente_codigo
left join core.grupos_cliente g on g.codigo = cl.grupo_codigo
where c.portal = 'pablo'
group by c.cliente_codigo, cl.razon_social, g.tipo;

revoke all on public.pablo_ventas, public.pablo_cobranzas, public.pablo_deuda, public.pablo_clientes
  from anon, authenticated, public;

-- 4. Usuario de base solo para el informe de Pablo (sin contraseña: la pone Cuci, ver paso a paso).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'looker_pablo') then
    create role looker_pablo nologin;
  end if;
end $$;
grant usage on schema public to looker_pablo;
grant select on public.pablo_ventas, public.pablo_cobranzas, public.pablo_deuda, public.pablo_clientes
  to looker_pablo;
-- Cuci tambien puede verlas con su usuario de Looker.
grant select on public.pablo_ventas, public.pablo_cobranzas, public.pablo_deuda, public.pablo_clientes
  to looker_lectura;

-- 5. Control: vendedor encontrado, clientes en la cartera y ventas por mes.
select 'vendedor: ' || p.vendedor_codigo || ' ' || coalesce(v.nombre, '?') as que, null::text as valor
from core.portal_vendedores p left join core.vendedores v on v.codigo = p.vendedor_codigo
where p.portal = 'pablo'
union all select 'clientes en la cartera', count(*)::text from calc.cartera_vendedor where portal = 'pablo'
union all select 'ventas ' || to_char(mes, 'YYYY-MM'), round(sum(neto), 0)::text
  from public.pablo_ventas where mes >= date_trunc('month', current_date) - interval '3 months' group by mes;
