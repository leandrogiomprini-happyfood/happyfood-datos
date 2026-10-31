-- 035_cartera_pablo_lista.sql
-- Cuci (31/10/2026): la cartera de Pablo por vendedor de Tekno deja afuera clientes que hoy atiende
-- (el vendedor no esta bien cargado en todos los comprobantes). Ahora la cartera es:
--   lista explicita de clientes (core.cartera_manual, cargada abajo por nombre)
--   + clientes cuyo ultimo comprobante tiene el vendedor de Pablo (como en la 033).
-- Para sumar un cliente: insert into core.cartera_manual values ('pablo', '<codigo Tekno>');
-- Para sacarlo:          delete from core.cartera_manual where portal = 'pablo' and cliente_codigo = '<codigo>';
-- Se puede volver a ejecutar sin riesgo.

create table if not exists core.cartera_manual (
  portal          text not null,
  cliente_codigo  text not null,
  primary key (portal, cliente_codigo)
);
alter table core.cartera_manual enable row level security;
revoke all on core.cartera_manual from anon, authenticated;

-- Lista de la planilla de cobranzas de Cuci (31/10/2026), buscada por razon social en Tekno.
create temporary table tmp_lista (patron text) on commit drop;
insert into tmp_lista values
  ('ASOCIACION ISRAELITA ARGENTINA TZEIRE%'), ('BELTRAMO%DUTTO%'), ('BEMA RIO%'), ('BIO SALUD%'),
  ('CASA GADY%'), ('CASTALDO LORENA%'), ('ANUTARA%'), ('ASOCIACION MUTUAL DE AYUDA%'),
  ('GABRIEL BONGIOVANNI%'), ('GALFRASCOLI%'), ('GAZZO%'), ('LUCONI%'), ('CONSUMIDOR FINAL%'),
  ('DISLE%'), ('DISTRIFLOP%'), ('EL ALMACEN%'), ('ETCHART%'), ('GREEN & CO%'), ('IBARRA MARIA%'),
  ('LAURA SPANGENBER%'), ('LIGA ARGENTINA DE PROTECCION%'), ('MANUEL QUIROGA%'), ('MARCELO GUTIERREZ%'),
  ('MARIA PAULA%'), ('MAXIMILIANO CALVI%'), ('MESAL%'), ('MORANZONI%'), ('MUZZIO%'), ('NORIEGA ROSANA%'),
  ('PAPORELLO%'), ('PEREYRA MARIANO%'), ('ROYAL VENDING%'), ('SOLER MELISA%'), ('SOPRUS%'),
  ('TU SANA ELECCION%'), ('TUCUMAN ENTRETENIMIENTO%');

insert into core.cartera_manual (portal, cliente_codigo)
select 'pablo', c.codigo
from tmp_lista t
join core.clientes c on c.razon_social ilike t.patron
on conflict do nothing;

-- Cartera = lista + vendedor de Tekno (columnas de la 033 + origen al final).
create or replace view calc.cartera_vendedor as
with ult as (
  select distinct on (cliente_codigo) cliente_codigo, vendedor_codigo, fecha
  from core.ventas_vigentes
  where cuenta_como_venta and signo = 1 and fecha >= current_date - 365 and cliente_codigo is not null
  order by cliente_codigo, fecha desc, orden desc
), por_vendedor as (
  select p.portal, u.cliente_codigo, u.vendedor_codigo, u.fecha, 'vendedor Tekno' as origen
  from ult u join core.portal_vendedores p on p.vendedor_codigo = u.vendedor_codigo
), por_lista as (
  select m.portal, m.cliente_codigo, u.vendedor_codigo, u.fecha, 'lista' as origen
  from core.cartera_manual m left join ult u on u.cliente_codigo = m.cliente_codigo
)
select portal, cliente_codigo, max(vendedor_codigo) as vendedor_codigo, max(fecha) as ultima_venta,
       string_agg(distinct origen, ' + ') as origen
from (select * from por_vendedor union all select * from por_lista) x
group by portal, cliente_codigo;

-- Control 1: nombres de la lista que no se encontraron en Tekno (revisar como estan escritos).
select 'NO ENCONTRADO: ' || t.patron as que, null::text as detalle
from tmp_lista t
where not exists (select 1 from core.clientes c where c.razon_social ilike t.patron)
union all
-- Control 2: clientes que entran solo por vendedor de Tekno (no estan en tu lista: confirmar).
select 'solo por vendedor Tekno: ' || c.cliente_codigo || ' ' || coalesce(cl.razon_social, ''), c.ultima_venta::text
from calc.cartera_vendedor c left join core.clientes cl on cl.codigo = c.cliente_codigo
where c.portal = 'pablo' and c.origen = 'vendedor Tekno'
union all
select 'clientes en la cartera', count(*)::text from calc.cartera_vendedor where portal = 'pablo';
