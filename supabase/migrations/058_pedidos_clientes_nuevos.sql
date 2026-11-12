-- 058_pedidos_clientes_nuevos.sql
-- Cuci (12/11/2026), clientes de la planilla de Pedidos:
--   Banco de Alimentos Cordoba: donacion (no se factura).
--   Blanch Benjamin Luis = Buenos Dias (cartera de Esteban).
--   Enrique Reyes S.A. = Ferniplast; CYRE S.A. = Cordiez (clientes nuevos de Esteban).
--   Farmar, Promacron, Gazzoni Fernando: distribuidores nuevos. Tristan Segovia: particular.
-- Los que todavia no estan en Tekno se valorizan con el precio promedio del producto y se emparejan
-- solos cuando se den de alta (si la razon social coincide). Se puede volver a ejecutar sin riesgo.

insert into core.pedidos_no_facturables values ('BANCO ALIMENTOS CORDOBA', 'donacion')
on conflict (cliente_pedido) do update set motivo = excluded.motivo;

-- Mapeo manual contra Tekno (solo si el cliente ya existe en Tekno).
insert into core.pedidos_cliente_map (cliente_pedido, cliente_codigo)
select pc.cliente, c.codigo
from calc.pedidos_cliente pc
join (values ('%Blanch%', '%BLANCH%'), ('%Enrique Reyes%', '%ENRIQUE REYES%'), ('%CYRE%', '%CYRE%')) as v(p_pedido, p_tekno)
  on pc.cliente ilike v.p_pedido
join lateral (select codigo from core.clientes where razon_social ilike v.p_tekno order by codigo limit 1) c on true
on conflict (cliente_pedido) do update set cliente_codigo = excluded.cliente_codigo;

-- Cartera de Esteban: Ferniplast y Cordiez figuran en Tekno con otra razon social.
insert into core.cartera_manual (portal, cliente_codigo)
select 'esteban', codigo from core.clientes
where razon_social ilike '%ENRIQUE REYES%' or razon_social ilike '%CYRE%'
on conflict do nothing;

-- Control.
select pc.cliente as en_pedidos, coalesce(pc.cliente_codigo, '(no esta en Tekno todavia)') as codigo,
       c.razon_social as en_tekno, pc.emparejado
from calc.pedidos_cliente pc left join core.clientes c on c.codigo = pc.cliente_codigo
where pc.cliente ilike any (array['%Blanch%', '%Enrique Reyes%', '%CYRE%', '%FARMAR%', '%PROMACRON%',
                                 '%GAZZONI%', '%Segovia%', '%BANCO ALIMENTOS%'])
union all
select 'TOTAL pendiente (sin IVA)', null, round(sum(monto_estimado))::text, null
from calc.pedidos_pendientes;
