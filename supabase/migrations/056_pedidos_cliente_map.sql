-- 056_pedidos_cliente_map.sql
-- Cuci (12/11/2026): clientes de la planilla de Pedidos que no emparejaban con Tekno.
-- Se puede volver a ejecutar sin riesgo.
insert into core.pedidos_cliente_map (cliente_pedido, cliente_codigo)
select pc.cliente, v.codigo
from calc.pedidos_cliente pc
join (values ('%PATAGONIA%', '00336'), ('%CENCOSUD%', '00331'), ('%COTO%', '00385')) as v(patron, codigo)
  on pc.cliente ilike v.patron
on conflict (cliente_pedido) do update set cliente_codigo = excluded.cliente_codigo;

select pc.cliente, pc.cliente_codigo, c.razon_social as en_tekno, pc.emparejado
from calc.pedidos_cliente pc left join core.clientes c on c.codigo = pc.cliente_codigo
where pc.cliente ilike any (array['%PATAGONIA%', '%CENCOSUD%', '%COTO%']) or pc.cliente_codigo is null
order by pc.emparejado, pc.cliente;
