-- 016_calc_stock_insumos.sql
-- Stock de insumos v1, recalculado solo cada vez que cambian las planillas (sin corridas manuales).
-- Logica del motor del proyecto "Stock de insumos en tiempo real" (docs/traspaso_stock_insumos.md §4),
-- version 1: el consumo sale de MEDIRLO entre conteos (diseño §10 y §16: "el consumo medido manda
-- sobre la receta"). La prevision con el plan semanal y las recetas va en la 017.
--
--   stock hoy = ultimo conteo completo + recepciones de OC posteriores - consumo diario x dias (min 0)
--   consumo diario = (conteo anterior + recibido en el medio - conteo siguiente) / dias,
--                    sobre los intervalos de los ultimos 56 dias
--   lead time = percentil 80 de (recepcion - pedido) del insumo; si tiene menos de 3 OC, el del
--               proveedor principal; si no, 15 dias
--   estado: sin stock | critico (dias < lead time) | atencion (< lead time + 14) | ok | sin consumo
-- Se puede volver a ejecutar sin riesgo.

create schema if not exists calc;

-- 1. Fechas de conteo validas: completas (al menos 80% de los insumos del conteo mas grande) y que no
--    sean copia de la anterior (regla 5: si >95% de los valores repite la semana previa, se descarta).
create or replace view calc.conteo_fechas as
with por_fecha as (
  select fecha, count(*) as insumos
  from core.conteo_insumos
  where fecha <= current_date
  group by fecha
), pares as (
  select a.fecha,
         count(*) as comparados,
         count(*) filter (where a.cantidad = b.cantidad) as iguales
  from core.conteo_insumos a
  join lateral (
    select max(fecha) as fecha_ant from por_fecha p where p.fecha < a.fecha
  ) ant on true
  join core.conteo_insumos b on b.insumo_codigo = a.insumo_codigo and b.fecha = ant.fecha_ant
  group by a.fecha
)
select p.fecha, p.insumos,
       p.insumos >= 0.8 * (select max(insumos) from por_fecha) as completo,
       coalesce(pa.iguales::numeric / nullif(pa.comparados, 0), 0) as proporcion_repetida,
       p.insumos >= 0.8 * (select max(insumos) from por_fecha)
         and coalesce(pa.iguales::numeric / nullif(pa.comparados, 0), 0) <= 0.95 as valido
from por_fecha p
left join pares pa on pa.fecha = p.fecha;

-- 2. Recepciones por insumo y dia (en unidad de insumo, ya corregidas en core.oc_lineas).
create or replace view calc.recepciones_dia as
select insumo_codigo, fecha_recepcion as fecha, sum(recibido_insumo) as recibido
from core.oc_lineas
where fecha_recepcion is not null and recibido_insumo > 0 and coalesce(estado, '') not ilike 'anul%'
group by 1, 2;

-- 3. Consumo medido entre conteos validos consecutivos.
create or replace view calc.consumo_intervalos as
with c as (
  select ci.insumo_codigo, ci.fecha, ci.cantidad
  from core.conteo_insumos ci
  join calc.conteo_fechas cf on cf.fecha = ci.fecha and cf.valido
), s as (
  select insumo_codigo, fecha as desde, cantidad as stock_desde,
         lead(fecha) over w as hasta, lead(cantidad) over w as stock_hasta
  from c
  window w as (partition by insumo_codigo order by fecha)
)
select s.insumo_codigo, s.desde, s.hasta, s.hasta - s.desde as dias,
       s.stock_desde, s.stock_hasta,
       coalesce((select sum(r.recibido) from calc.recepciones_dia r
                 where r.insumo_codigo = s.insumo_codigo and r.fecha > s.desde and r.fecha <= s.hasta), 0) as recibido,
       s.stock_desde
         + coalesce((select sum(r.recibido) from calc.recepciones_dia r
                     where r.insumo_codigo = s.insumo_codigo and r.fecha > s.desde and r.fecha <= s.hasta), 0)
         - s.stock_hasta as consumo
from s
where s.hasta is not null and s.hasta > s.desde;

-- 4. Lead time (percentil 80) por insumo y por proveedor.
create or replace view calc.lead_time as
with ent as (
  select insumo_codigo, proveedor, dias_entrega
  from core.oc_lineas
  where dias_entrega between 0 and 365 and fecha_pedido >= current_date - 730
), por_insumo as (
  select insumo_codigo, count(*) as ocs,
         percentile_cont(0.8) within group (order by dias_entrega) as p80
  from ent group by insumo_codigo
), por_proveedor as (
  select proveedor, percentile_cont(0.8) within group (order by dias_entrega) as p80
  from ent group by proveedor having count(*) >= 3
), principal as (
  select distinct on (insumo_codigo) insumo_codigo, proveedor
  from core.insumos_proveedores
  where coalesce(estado_proveedor, '') ilike 'vigente%'
  order by insumo_codigo, (tipo = 'Principal') desc, proveedor
)
select i.codigo as insumo_codigo,
       pr.proveedor as proveedor_principal,
       pi.ocs,
       round(coalesce(case when pi.ocs >= 3 then pi.p80 end, pp.p80, pi.p80, 15)::numeric, 0) as lead_time,
       case when pi.ocs >= 3 then 'insumo' when pp.p80 is not null then 'proveedor'
            when pi.p80 is not null then 'insumo (pocas OC)' else 'por defecto' end as fuente_lead_time
from core.insumos i
left join por_insumo pi on pi.insumo_codigo = i.codigo
left join principal pr on pr.insumo_codigo = i.codigo
left join por_proveedor pp on pp.proveedor = pr.proveedor;

-- 5. OC en camino (no recibidas ni anuladas).
create or replace view calc.oc_pendientes as
select insumo_codigo, oc, proveedor, fecha_pedido, fecha_prometida,
       pedido_insumo as cantidad,
       fecha_prometida < current_date as atrasada
from core.oc_lineas
where fecha_recepcion is null
  and coalesce(estado, '') !~* '^(anul|entregado$|ev-entregado)'
  and coalesce(pedido_insumo, 0) > 0;

-- 6. Stock de insumos hoy.
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
         pend.en_camino, pend.proxima_entrega, pend.hay_atrasadas,
         current_date - b.fecha_conteo as dias_desde_conteo
  from base b
  left join core.insumos i on i.codigo = b.insumo_codigo
  left join rec on rec.insumo_codigo = b.insumo_codigo
  left join cons on cons.insumo_codigo = b.insumo_codigo
  left join calc.lead_time lt on lt.insumo_codigo = b.insumo_codigo
  left join pend on pend.insumo_codigo = b.insumo_codigo
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
         when stock_hoy <= 0 then 'sin stock'
         when coalesce(consumo_diario, 0) <= 0 then 'sin consumo'
         when stock_hoy / consumo_diario < lead_time then 'crítico'
         when stock_hoy / consumo_diario < lead_time + 14 then 'atención'
         else 'ok'
       end as estado,
       case when consumo_diario > 0
            then greatest(round(consumo_diario * (lead_time + 14) - stock_hoy - coalesce(en_camino, 0), 1), 0)
       end as sugerido_pedir,
       intervalos_negativos > 0 as revisar_conteo
from calc2;

-- 7. Para Looker.
create or replace view public.reporte_stock_insumos as select * from calc.stock_insumos;
revoke all on public.reporte_stock_insumos from anon, authenticated, public;
grant select on public.reporte_stock_insumos to looker_lectura;

-- 8. Control.
select estado, count(*) as insumos from calc.stock_insumos group by estado
union all select 'ultimo conteo valido: ' || max(fecha)::text, null from calc.conteo_fechas where valido
union all select 'conteos descartados: ' || coalesce(string_agg(fecha::text, ', ' order by fecha), 'ninguno'), null
  from calc.conteo_fechas where not valido
order by 2 desc nulls last;
