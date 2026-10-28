-- 017_insumos_lugares_y_por_pedido.sql
-- Ajustes al stock de insumos (016) con lo que confirmo Cuci el 28/10/2026:
--   1. Un mismo codigo aparece en varias filas del conteo porque se cuenta en distintos lugares
--      (planta, deposito y transito; se envia de uno a otro). El stock del codigo es la SUMA.
--   2. Insumos "por pedido": flexibles de exportacion (diseño Chile y Portugues/Brasil) y Chocosoja
--      (cuenta de elaboracion). Se usan a demanda y no hay envios previstos: no generan alertas,
--      siguen visibles con estado "por pedido". Para sumar o quitar uno: insert/delete en
--      core.insumos_config.
-- Se puede volver a ejecutar sin riesgo.

-- 1. Conteo por lugar (detalle) y conteo por codigo (suma de lugares).
create or replace view core.conteo_insumos_detalle as
with fechas as (
  select (x.ord - 1)::int as idx, hojas.fecha(x.v) as fecha
  from hojas.filas f, jsonb_array_elements(f.valores) with ordinality as x(v, ord)
  where f.fuente = 'conteo_stock' and f.fila = 3 and x.ord >= 7 and (x.ord - 7) % 4 = 0
)
select r.fila,
       hojas.num(r.valores -> 0)::int  as insumo_codigo,
       hojas.txt(r.valores -> 1)       as insumo,
       fe.fecha,
       hojas.num(r.valores -> fe.idx)  as cantidad
from hojas.filas r
join fechas fe on fe.fecha is not null
where r.fuente = 'conteo_stock' and r.fila > 3
  and hojas.num(r.valores -> 0) is not null
  and hojas.num(r.valores -> fe.idx) is not null;

create or replace view core.conteo_insumos as
select insumo_codigo, min(insumo) as insumo, fecha, sum(cantidad) as cantidad
from core.conteo_insumos_detalle
group by insumo_codigo, fecha;

-- 2. Configuracion por insumo.
create table if not exists core.insumos_config (
  insumo_codigo int primary key,
  modo          text not null default 'regular' check (modo in ('regular', 'por_pedido')),
  motivo        text,
  actualizado   timestamptz not null default now()
);
alter table core.insumos_config enable row level security;
revoke all on core.insumos_config from anon, authenticated;

insert into core.insumos_config (insumo_codigo, modo, motivo) values
  (266, 'por_pedido', 'Flexible exportacion: diseño Chile'),
  (267, 'por_pedido', 'Flexible exportacion: diseño Chile'),
  (273, 'por_pedido', 'Flexible exportacion: diseño Chile'),
  (196, 'por_pedido', 'Flexible exportacion: diseño Portugues (Brasil)'),
  (197, 'por_pedido', 'Flexible exportacion: diseño Portugues (Brasil)'),
  (198, 'por_pedido', 'Flexible exportacion: diseño Portugues (Brasil)'),
  (250, 'por_pedido', 'Chocosoja en cuenta de elaboracion: a demanda')
on conflict (insumo_codigo) do update set modo = excluded.modo, motivo = excluded.motivo, actualizado = now();

-- 3. Stock de insumos hoy (igual que la 016, con el modo por pedido; columna nueva al final).
create or replace view calc.stock_insumos as
with ult as (
  select max(fecha) as fecha from calc.conteo_fechas where valido
), base as (
  select ci.insumo_codigo, ci.insumo as insumo_conteo, ci.cantidad as conteo, ci.fecha as fecha_conteo
  from core.conteo_insumos ci, ult
  where ci.fecha = ult.fecha
), cons as (
  select insumo_codigo,
         sum(consumo) filter (where consumo >= 0) as consumo_total,
         sum(dias) filter (where consumo >= 0) as dias,
         count(*) filter (where consumo < 0) as intervalos_negativos
  from calc.consumo_intervalos
  where hasta > current_date - 56
  group by insumo_codigo
), rec as (
  select b.insumo_codigo, coalesce(sum(r.recibido), 0) as recibido
  from base b left join calc.recepciones_dia r on r.insumo_codigo = b.insumo_codigo and r.fecha > b.fecha_conteo
  group by b.insumo_codigo
), pend as (
  select insumo_codigo, sum(cantidad) as en_camino, min(fecha_prometida) as proxima_entrega,
         bool_or(atrasada) as hay_atrasadas
  from calc.oc_pendientes group by insumo_codigo
), calc1 as (
  select b.*, i.nombre as insumo_compras, i.unidad, i.estado as estado_compras,
         rec.recibido as recibido_desde_conteo,
         case when cons.dias > 0 then cons.consumo_total / cons.dias end as consumo_diario,
         cons.intervalos_negativos,
         lt.lead_time, lt.fuente_lead_time, lt.proveedor_principal,
         coalesce(cfg.modo, 'regular') as modo,
         pend.en_camino, pend.proxima_entrega, pend.hay_atrasadas,
         current_date - b.fecha_conteo as dias_desde_conteo
  from base b
  left join core.insumos i on i.codigo = b.insumo_codigo
  left join rec on rec.insumo_codigo = b.insumo_codigo
  left join cons on cons.insumo_codigo = b.insumo_codigo
  left join calc.lead_time lt on lt.insumo_codigo = b.insumo_codigo
  left join pend on pend.insumo_codigo = b.insumo_codigo
  left join core.insumos_config cfg on cfg.insumo_codigo = b.insumo_codigo
), calc2 as (
  select c.*,
         greatest(c.conteo + c.recibido_desde_conteo - coalesce(c.consumo_diario, 0) * c.dias_desde_conteo, 0) as stock_hoy
  from calc1 c
)
select insumo_codigo,
       coalesce(insumo_compras, insumo_conteo) as insumo,
       unidad,
       fecha_conteo, conteo, recibido_desde_conteo,
       round(coalesce(consumo_diario, 0) * dias_desde_conteo, 3) as consumo_desde_conteo,
       round(stock_hoy, 3) as stock_hoy,
       round(consumo_diario, 4) as consumo_diario,
       case when consumo_diario > 0 then round(stock_hoy / consumo_diario, 1) end as dias_cobertura,
       case when consumo_diario > 0 then current_date + floor(stock_hoy / consumo_diario)::int end as fecha_quiebre,
       lead_time, fuente_lead_time, proveedor_principal,
       en_camino, proxima_entrega, coalesce(hay_atrasadas, false) as oc_atrasada,
       case
         when modo = 'por_pedido' then 'por pedido'
         when stock_hoy <= 0 then 'sin stock'
         when coalesce(consumo_diario, 0) <= 0 then 'sin consumo'
         when stock_hoy / consumo_diario < lead_time then 'crítico'
         when stock_hoy / consumo_diario < lead_time + 14 then 'atención'
         else 'ok'
       end as estado,
       case when consumo_diario > 0 and modo <> 'por_pedido'
            then greatest(round(consumo_diario * (lead_time + 14) - stock_hoy - coalesce(en_camino, 0), 1), 0)
       end as sugerido_pedir,
       intervalos_negativos > 0 as revisar_conteo,
       modo
from calc2;

-- 4. Vista para Looker con la columna nueva.
create or replace view public.reporte_stock_insumos as select * from calc.stock_insumos;
revoke all on public.reporte_stock_insumos from anon, authenticated, public;
grant select on public.reporte_stock_insumos to looker_lectura;

-- 5. Control.
select estado, count(*) as insumos from calc.stock_insumos group by estado
union all select 'codigos contados en mas de un lugar: ' || count(*)::text, null
  from (select insumo_codigo from core.conteo_insumos_detalle
        where fecha = (select max(fecha) from calc.conteo_fechas where valido)
        group by insumo_codigo having count(*) > 1) x
order by 2 desc nulls last;
