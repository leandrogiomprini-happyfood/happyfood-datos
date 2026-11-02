-- 046_cartera_pablo_chang.sql
-- Cuci (02/11/2026): CHANG SHUN HO es cliente de Pablo. Se suma a su lista fija.
-- Se puede volver a ejecutar sin riesgo.
insert into core.cartera_manual (portal, cliente_codigo)
select 'pablo', codigo from core.clientes where razon_social ilike '%CHANG%'
on conflict do nothing;

select c.codigo, c.razon_social, v.origen, v.ultima_venta
from core.clientes c
left join calc.cartera_vendedor v on v.portal = 'pablo' and v.cliente_codigo = c.codigo
where c.razon_social ilike '%CHANG%';
