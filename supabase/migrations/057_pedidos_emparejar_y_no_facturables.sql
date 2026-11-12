-- 057_pedidos_emparejar_y_no_facturables.sql
-- Revision de la 055 con los datos reales (12/11/2026):
--   * el emparejado por nombre fallaba por puntos y sufijos ("ANUTARA SRL" vs "ANUTARA S.R.L.").
--     Ahora compara sin puntuacion, sin acentos y sin S.A., SRL, SAS, SACI, CICSA, LLC, CO; primero
--     igual, despues uno contenido en el otro (al menos 6 letras). El mapeo manual sigue mandando.
--   * pedidos que no se facturan (consumo interno, reclamos, muestras, donaciones): monto 0 y
--     origen_precio = 'no se factura'. Lista en core.pedidos_no_facturables.
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

create table if not exists core.pedidos_no_facturables (
  cliente_pedido text primary key,
  motivo         text
);
alter table core.pedidos_no_facturables enable row level security;
revoke all on core.pedidos_no_facturables from anon, authenticated;

insert into core.pedidos_no_facturables values
  ('CONSUMO INTERNO', 'consumo interno'), ('RECLAMO', 'reposicion por reclamo'),
  ('Muestra clientes', 'muestras'), ('LAPDI', 'donacion (cliente interno)')
on conflict (cliente_pedido) do nothing;

create or replace function calc.norm_razon(t text)
returns text language sql immutable as $$
  select btrim(regexp_replace(
           regexp_replace(
             ' ' || regexp_replace(upper(translate(coalesce(t, ''), 'áéíóúÁÉÍÓÚñÑüÜ', 'AEIOUAEIOUNNUU')), '[^A-Z0-9 ]', '', 'g') || ' ',
             ' (SA|SRL|SAS|SACI|SACIF|SAIC|CICSA|CIC|LLC|CO|SH|SC) ', ' ', 'g'),
           '\s+', ' ', 'g'))
$$;

create or replace view calc.pedidos_cliente as
with nombres as (
  select distinct cliente from core.pedidos where cliente is not null
  union
  select distinct cliente from core.pedidos_detalle where cliente is not null
), norm as (
  select cliente, calc.norm_razon(cliente) as n from nombres
), cli as (
  select codigo, calc.norm_razon(razon_social) as n from core.clientes
)
select x.cliente,
       coalesce(m.cliente_codigo,
                (select c.codigo from cli c where c.n = x.n limit 1),
                (select c.codigo from cli c
                 where length(x.n) >= 6 and length(c.n) >= 6 and (c.n like '%' || x.n || '%' or x.n like '%' || c.n || '%')
                 order by abs(length(c.n) - length(x.n)) limit 1)) as cliente_codigo,
       case when m.cliente_codigo is not null then 'manual'
            when exists (select 1 from cli c where c.n = x.n) then 'exacto'
            when exists (select 1 from cli c where length(x.n) >= 6 and length(c.n) >= 6
                         and (c.n like '%' || x.n || '%' or x.n like '%' || c.n || '%')) then 'parecido'
            else 'sin emparejar' end as emparejado
from norm x
left join core.pedidos_cliente_map m on m.cliente_pedido = x.cliente;

create or replace view calc.pedidos_pendientes as
with ped as (
  select p.pedido, p.fecha, p.entrega_prevista, p.cliente, p.orden_compra, p.tipo_cliente, p.lista_precio,
         p.tipo_facturacion
  from core.pedidos p
  where p.estado = 'Pendiente'
), lin as (
  select ped.*, d.linea, d.producto_codigo, d.producto, coalesce(d.solicitado, 0) as cantidad
  from ped join core.pedidos_detalle d on d.pedido = ped.pedido
  where coalesce(d.solicitado, 0) > 0
)
select l.pedido, l.fecha, l.entrega_prevista, l.cliente, pc.cliente_codigo, pc.emparejado,
       l.orden_compra, l.tipo_cliente, l.lista_precio, l.tipo_facturacion,
       l.linea, l.producto_codigo, coalesce(prd.producto, l.producto) as producto,
       coalesce(prd.familia, 'SIN CLASIFICAR') as familia,
       l.cantidad,
       round(l.cantidad * prd.kg_por, 2) as kilos,
       case when nf.cliente_pedido is not null then 0
            else round(coalesce(p1.precio, p2.precio, p3.precio), 2) end as precio_unitario,
       case when nf.cliente_pedido is not null then 'no se factura'
            when p1.precio is not null then 'último del cliente'
            when p2.precio is not null then 'promedio 60 días'
            when p3.precio is not null then 'promedio 12 meses'
            else 'sin precio' end as origen_precio,
       case when nf.cliente_pedido is not null then 0
            else round(l.cantidad * coalesce(p1.precio, p2.precio, p3.precio), 2) end as monto_estimado
from lin l
left join calc.pedidos_cliente pc on pc.cliente = l.cliente
left join core.pedidos_no_facturables nf on upper(btrim(nf.cliente_pedido)) = upper(btrim(l.cliente))
left join core.productos prd on prd.codigo = l.producto_codigo::text
left join lateral (
  select v.precio from calc.precios_venta v
  where v.cliente_codigo = pc.cliente_codigo and v.producto_codigo = l.producto_codigo::text
    and v.fecha >= current_date - 180
  order by v.fecha desc limit 1
) p1 on true
left join lateral (
  select avg(v.precio) as precio from calc.precios_venta v
  where v.producto_codigo = l.producto_codigo::text and v.fecha >= current_date - 60
) p2 on true
left join lateral (
  select avg(v.precio) as precio from calc.precios_venta v
  where v.producto_codigo = l.producto_codigo::text
) p3 on true;


-- Control: como quedo cada nombre de la planilla (los 'parecido' conviene revisarlos).
select pc.emparejado, pc.cliente as en_pedidos, pc.cliente_codigo, c.razon_social as en_tekno,
       case when nf.cliente_pedido is not null then 'no se factura' end as nota
from calc.pedidos_cliente pc
left join core.clientes c on c.codigo = pc.cliente_codigo
left join core.pedidos_no_facturables nf on upper(btrim(nf.cliente_pedido)) = upper(btrim(pc.cliente))
where pc.emparejado <> 'exacto'
order by case pc.emparejado when 'sin emparejar' then 1 when 'parecido' then 2 else 3 end, pc.cliente;
