-- 037_cartera_pablo_agregados.sql
-- Cuci (31/10/2026): GLUTEN FREE NEUQUEN, CHIQUI y CAPOTE son de Pablo; se fijan en la lista para no
-- depender del vendedor cargado en Tekno. Ya ejecutado a mano en Supabase; queda como registro.
-- Se puede volver a ejecutar sin riesgo.
insert into core.cartera_manual (portal, cliente_codigo)
select 'pablo', codigo from core.clientes
where razon_social ilike 'GLUTEN FREE NEUQUEN%' or razon_social ilike 'CHIQUI%' or razon_social ilike 'CAPOTE%'
on conflict do nothing;
