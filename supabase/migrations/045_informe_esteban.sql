-- 045_informe_esteban.sql
-- Informe de Looker para Esteban (pedido de Cuci, 02/11/2026), igual al de Pablo (033 + 035):
-- ventas, cobranzas, deuda y clientes de SU cartera, sin costos ni margen.
--   * cartera = lista fija (core.cartera_manual, portal 'esteban') + clientes cuyo ultimo comprobante
--     tiene el vendedor de Esteban en Tekno (core.portal_vendedores, buscado por nombre "ESTEBAN");
--   * vistas public.esteban_* y usuario de base looker_esteban (solo lee esas vistas; sin contraseña
--     hasta que Cuci la ponga).
-- Lista de Cuci: Tadicor, Mesal, Buenos Dias (Benjamin Blanch), Superimperio, Simple Distribucion,
-- Dinosaurio (ya no se le vende, queda por el historico). Ferniplast y Cordiez todavia no son
-- clientes: si no estan en Tekno, salen como NO ENCONTRADO y se agregan cuando se den de alta.
-- Para sumar un cliente despues: insert into core.cartera_manual values ('esteban', '<codigo Tekno>');
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- 1. Vendedor de Esteban en Tekno.
insert into core.portal_vendedores (portal, vendedor_codigo)
select 'esteban', codigo from core.vendedores where nombre ilike '%esteban%'
on conflict do nothing;

-- 2. Lista fija.
create temporary table tmp_lista (patron text) on commit drop;
insert into tmp_lista values
  ('%TADICOR%'), ('MESAL%'), ('%BUENOS DIAS%'), ('%BLANCH%'), ('%IMPERIO%'),
  ('%FERNIPLAST%'), ('%CORDIEZ%'), ('%SIMPLE DISTRIB%'), ('%DINOSAURIO%');

insert into core.cartera_manual (portal, cliente_codigo)
select 'esteban', c.codigo
from tmp_lista t join core.clientes c on c.razon_social ilike t.patron
on conflict do nothing;

-- 3. Vistas del informe (mismas columnas que las de Pablo).
create or replace view public.esteban_ventas as
select v.fecha, v.mes, v.anio, v.canal_fiscal, v.tipo_comprobante, v.comprobante,
       v.cliente_codigo, v.cliente, v.grupo_cliente, v.tipo_cliente,
       v.producto_codigo, v.producto, v.familia, v.es_flete,
       v.cantidad, v.unidades, v.kilos, v.neto
from rpt.ventas_analisis v
join calc.cartera_vendedor c on c.portal = 'esteban' and c.cliente_codigo = v.cliente_codigo;

create or replace view public.esteban_cobranzas as
select k.fecha_cobro, k.mes, k.recibo, k.cliente_codigo, k.cliente, k.tipo_cliente, k.canal_fiscal,
       k.comprobante_tipo, k.comprobante, k.fecha_comprobante, k.dias_al_cobro,
       k.cobrado_total, k.cobrado_neto, k.a_cuenta
from rpt.cobranzas_neto k
join calc.cartera_vendedor c on c.portal = 'esteban' and c.cliente_codigo = k.cliente_codigo;

create or replace view public.esteban_deuda as
select d.cliente_codigo, d.cliente, d.comprobante, d.tipo_comprobante, d.fecha_comprobante,
       d.fecha_vencimiento, d.saldo, d.dias_vencido, d.tramo
from rpt.cobranzas_pendientes d
join calc.cartera_vendedor c on c.portal = 'esteban' and c.cliente_codigo = d.cliente_codigo;

-- Un renglon por cliente: ultima compra y comparacion de los ultimos 90 dias contra los 90 anteriores.
create or replace view public.esteban_clientes as
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
where c.portal = 'esteban'
group by c.cliente_codigo, cl.razon_social, g.tipo;

revoke all on public.esteban_ventas, public.esteban_cobranzas, public.esteban_deuda, public.esteban_clientes
  from anon, authenticated, public;

-- 4. Usuario de base solo para el informe de Esteban.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'looker_esteban') then
    create role looker_esteban nologin;
  end if;
end $$;
grant usage on schema public to looker_esteban;
grant select on public.esteban_ventas, public.esteban_cobranzas, public.esteban_deuda, public.esteban_clientes
  to looker_esteban, looker_lectura;

-- 5. Control.
select 'vendedor: ' || p.vendedor_codigo || ' ' || coalesce(v.nombre, '?') as que, null::text as detalle
from core.portal_vendedores p left join core.vendedores v on v.codigo = p.vendedor_codigo
where p.portal = 'esteban'
union all
select 'NO ENCONTRADO: ' || t.patron, null
from tmp_lista t where not exists (select 1 from core.clientes c where c.razon_social ilike t.patron)
union all
select 'en la cartera: ' || c.cliente_codigo || ' ' || coalesce(cl.razon_social, ''),
       c.origen || coalesce(' · ultima venta ' || c.ultima_venta, ' · sin ventas en 12 meses')
from calc.cartera_vendedor c left join core.clientes cl on cl.codigo = c.cliente_codigo
where c.portal = 'esteban'
union all
select 'ventas ' || to_char(mes, 'YYYY-MM'), round(sum(neto), 0)::text
from public.esteban_ventas where mes >= date_trunc('month', current_date) - interval '3 months' group by mes;
