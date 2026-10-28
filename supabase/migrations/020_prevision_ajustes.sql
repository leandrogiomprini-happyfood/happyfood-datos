-- 020_prevision_ajustes.sql
-- Revision de la 019 con datos reales (28/10/2026):
--   * Hoy el plan tiene un lote grande de DDL sin azucar (5.400 bandejas teoricas del flexible 116, 39
--     veces el promedio diario de las ultimas 8 semanas). El metodo de la 019 multiplicaba el consumo
--     medido por esa proporcion. Para el empaque esta bien (convierte unidades a kg de film), pero en
--     ingredientes arrastraba un factor medido/receta de 2,1 en el Baño Chocolate Diet.
--   * Cambio: consumo previsto de un dia = teorico del plan x factor del insumo.
--       ingredientes: factor = medido / teorico, limitado entre 0,8 y 1,6 (merma razonable); si no hay
--                     teorico historico, 1,42 (mediana medida en el diseño §17).
--       empaque:      factor = medido / teorico, sin limite (es la conversion de unidades a kg de film);
--                     si no hay teorico historico, se usa el consumo medido.
--   * Rendimiento: el recalculo tardaba 25 s. Se reescriben las dos vistas mas lentas (consumo entre
--     conteos y validacion de conteos) sin subconsultas por fila.
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- 1. Validacion de conteos sin subconsulta por fila (mismas columnas).
create or replace view calc.conteo_fechas as
with por_fecha as (
  select fecha, count(*) as insumos
  from core.conteo_insumos
  where fecha <= current_date
  group by fecha
), con_ant as (
  select fecha, insumos, lag(fecha) over (order by fecha) as fecha_ant from por_fecha
), pares as (
  select ca.fecha,
         count(*) as comparados,
         count(*) filter (where a.cantidad = b.cantidad) as iguales
  from con_ant ca
  join core.conteo_insumos a on a.fecha = ca.fecha
  join core.conteo_insumos b on b.fecha = ca.fecha_ant and b.insumo_codigo = a.insumo_codigo
  group by ca.fecha
)
select p.fecha, p.insumos,
       p.insumos >= 0.8 * (select max(insumos) from por_fecha) as completo,
       coalesce(pa.iguales::numeric / nullif(pa.comparados, 0), 0) as proporcion_repetida,
       p.insumos >= 0.8 * (select max(insumos) from por_fecha)
         and coalesce(pa.iguales::numeric / nullif(pa.comparados, 0), 0) <= 0.95 as valido
from por_fecha p
left join pares pa on pa.fecha = p.fecha;

-- 2. Consumo entre conteos con un solo join a las recepciones (mismas columnas).
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
), rec as (
  select s.insumo_codigo, s.desde, coalesce(sum(r.recibido), 0) as recibido
  from s
  left join calc.recepciones_dia r
    on r.insumo_codigo = s.insumo_codigo and r.fecha > s.desde and r.fecha <= s.hasta
  where s.hasta is not null
  group by s.insumo_codigo, s.desde
)
select s.insumo_codigo, s.desde, s.hasta, s.hasta - s.desde as dias,
       s.stock_desde, s.stock_hasta, rec.recibido,
       s.stock_desde + rec.recibido - s.stock_hasta as consumo
from s
join rec on rec.insumo_codigo = s.insumo_codigo and rec.desde = s.desde
where s.hasta > s.desde;

-- 3. Factor por insumo.
create or replace view calc.factor_insumo as
with hist as (
  select insumo_codigo, sum(cantidad) / 56.0 as teorico_dia from calc.teorico_real group by 1
), ingr as (
  select distinct insumo_codigo from core.recetas
)
select s.insumo_codigo,
       case when i.insumo_codigo is not null then 'ingrediente' else 'empaque' end as tipo,
       h.teorico_dia,
       s.consumo_diario,
       case
         when i.insumo_codigo is not null then
           case when coalesce(h.teorico_dia, 0) > 0 and s.consumo_diario > 0
                then least(greatest(s.consumo_diario / h.teorico_dia, 0.8), 1.6)
                else 1.42 end
         else
           case when coalesce(h.teorico_dia, 0) > 0 and s.consumo_diario > 0
                then s.consumo_diario / h.teorico_dia end
       end as factor
from calc.stock_insumos s
left join hist h on h.insumo_codigo = s.insumo_codigo
left join ingr i on i.insumo_codigo = s.insumo_codigo;

-- 4. Stock dia por dia (mismas columnas que la 019 + factor al final).
create or replace view calc.prevision_dia as
with fin as (
  select max(fecha) as plan_hasta from core.plan_produccion where fecha >= current_date
), hist as (
  select insumo_codigo, sum(cantidad) / 56.0 as teorico_dia from calc.teorico_real group by 1
), ingr as (
  select distinct insumo_codigo from core.recetas
), f as (
  -- mismo calculo que calc.factor_insumo, en linea para no recalcular el stock dos veces
  select s.insumo_codigo, s.stock_hoy, s.consumo_diario, h.teorico_dia,
         case when i.insumo_codigo is not null then 'ingrediente' else 'empaque' end as tipo,
         case
           when i.insumo_codigo is not null then
             case when coalesce(h.teorico_dia, 0) > 0 and s.consumo_diario > 0
                  then least(greatest(s.consumo_diario / h.teorico_dia, 0.8), 1.6)
                  else 1.42 end
           else
             case when coalesce(h.teorico_dia, 0) > 0 and s.consumo_diario > 0
                  then s.consumo_diario / h.teorico_dia end
         end as factor
  from calc.stock_insumos s
  left join hist h on h.insumo_codigo = s.insumo_codigo
  left join ingr i on i.insumo_codigo = s.insumo_codigo
), d as (
  select f.*, fin.plan_hasta, g::date as dia,
         f.factor is not null and fin.plan_hasta is not null and g::date <= fin.plan_hasta
           and (f.tipo = 'ingrediente' or coalesce(f.teorico_dia, 0) > 0) as segun_plan
  from f
  cross join fin
  cross join generate_series(current_date, current_date + 180, interval '1 day') g
)
select d.insumo_codigo, d.dia,
       case when d.segun_plan then coalesce(tp.cantidad, 0) * d.factor
            else coalesce(d.consumo_diario, 0) end as consumo,
       d.segun_plan,
       d.stock_hoy,
       d.factor
from d
left join calc.teorico_plan tp on tp.insumo_codigo = d.insumo_codigo and tp.fecha = d.dia;

-- 5. Recalcular y controlar.
select calc.refrescar_insumos();

select 'estado con plan: ' || estado_plan as que, count(*)::text as valor
from rpt.stock_insumos group by estado_plan
union all select 'recalculo (segundos)', duracion_s::text from rpt.ultimo_recalculo_insumos
union all
select * from (
  select 'con plan: ' || s.insumo || ' (' || s.insumo_codigo || ')',
         coalesce(s.dias_cobertura::text, '-') || ' d promedio -> ' || s.dias_cobertura_plan || ' d con plan · factor '
           || coalesce(round(fi.factor, 3)::text, '-') || ' (' || fi.tipo || ')'
  from rpt.stock_insumos s
  join calc.factor_insumo fi on fi.insumo_codigo = s.insumo_codigo
  where s.usa_plan and s.dias_cobertura_plan < 181 and s.dias_cobertura is not null
    and s.dias_cobertura_plan < s.dias_cobertura - 2
  order by s.dias_cobertura_plan
  limit 15
) x;
