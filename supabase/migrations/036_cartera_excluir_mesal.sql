-- 036_cartera_excluir_mesal.sql
-- Cuci (31/10/2026): MESAL no es de Pablo, es de Esteban.
-- Se agrega una lista de exclusion: un cliente excluido no entra en la cartera ni por la lista ni por
-- el vendedor de Tekno (por si alguna factura de MESAL salio con el vendedor de Pablo).
-- Para excluir otro: insert into core.cartera_excluida values ('pablo', '<codigo Tekno>');
-- Correr DESPUES de la 035. Se puede volver a ejecutar sin riesgo.

create table if not exists core.cartera_excluida (
  portal          text not null,
  cliente_codigo  text not null,
  primary key (portal, cliente_codigo)
);
alter table core.cartera_excluida enable row level security;
revoke all on core.cartera_excluida from anon, authenticated;

insert into core.cartera_excluida (portal, cliente_codigo)
select 'pablo', c.codigo from core.clientes c where c.razon_social ilike 'MESAL%'
on conflict do nothing;

delete from core.cartera_manual m
using core.cartera_excluida e
where e.portal = m.portal and e.cliente_codigo = m.cliente_codigo;

-- Misma vista de la 035, sin los excluidos.
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
where not exists (select 1 from core.cartera_excluida e
                  where e.portal = x.portal and e.cliente_codigo = x.cliente_codigo)
group by portal, cliente_codigo;

-- Control.
select 'excluido: ' || e.cliente_codigo || ' ' || coalesce(c.razon_social, '') as que,
       case when exists (select 1 from calc.cartera_vendedor v
                         where v.portal = e.portal and v.cliente_codigo = e.cliente_codigo)
            then 'SIGUE EN LA CARTERA (avisar)' else 'fuera de la cartera' end as detalle
from core.cartera_excluida e left join core.clientes c on c.codigo = e.cliente_codigo
where e.portal = 'pablo'
union all
select 'clientes en la cartera', count(*)::text from calc.cartera_vendedor where portal = 'pablo';
