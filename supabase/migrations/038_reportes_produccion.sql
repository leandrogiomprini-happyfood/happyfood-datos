-- 038_reportes_produccion.sql
-- Informe "HappyFood · Produccion" (jefe de planta y direccion). Todo sale de datos que ya entran solos:
-- parte de produccion, masas, plan semanal, stock de PT, ventas y costos por kg.
--   calc.produccion_kg          un renglon por parte, en bultos equivalentes y kg
--   public.reporte_produccion        producido por dia/producto (sin costos)       -> planta y direccion
--   public.reporte_plan_vs_real      plan contra real por semana y producto        -> planta y direccion
--   public.reporte_masas             masas declaradas y scrap de masa por dia      -> planta y direccion
--   public.reporte_stock_pt          stock de PT por lote, vencimiento, dias venta -> planta y direccion
--   public.reporte_produccion_costo  producido valorizado al costo por kg          -> solo direccion
-- El historico arranca el 01/03/2025 (oct-2024 a feb-2025 el parte esta incompleto).
-- Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- 1. Parte de produccion en bultos equivalentes y kg.
--    Bandejas de semielaborado (2xx1): se pasan al bulto 3xx1 (30 bandejas), igual que en insumos.
--    Armados (displays rearmados) y Rearmado/Retrabajo no son produccion nueva: quedan marcados.
create or replace view calc.produccion_kg as
with p as (
  select pp.*,
         case when pp.unidad_cantidad = 'bandejas'
              then ('3' || substring(lpad(pp.producto_codigo::text, 4, '0'), 2, 3))::int
              else pp.producto_codigo end as producto_bulto,
         case when pp.unidad_cantidad = 'bandejas' then pp.cantidad / 30.0 else pp.cantidad end as bultos_eq
  from core.produccion_partes pp
  where pp.fecha >= date '2025-03-01' and pp.fecha <= current_date and pp.cantidad > 0
)
select p.fila, p.fecha,
       date_trunc('week', p.fecha)::date                         as semana,
       date_trunc('month', p.fecha)::date                        as mes,
       p.producto_bulto                                          as producto_codigo,
       coalesce(prd.producto, p.producto)                        as producto,
       coalesce(prd.familia, 'SIN CLASIFICAR')                   as familia,
       p.unidad_cantidad,
       coalesce(p.tipo, '')                                      as tipo,
       p.unidad_cantidad <> 'armado'
         and coalesce(p.tipo, '') not in ('Rearmado', 'Retrabajo') as es_produccion,
       p.cantidad                                                as cantidad_parte,
       round(p.bultos_eq, 3)                                     as bultos,
       round(p.bultos_eq * prd.kg_por, 3)                        as kilos,
       coalesce(p.scrap_producto, 0)                             as scrap_producto,
       coalesce(p.scrap_flexible, 0)                             as scrap_flexible,
       p.masas_declaradas,
       p.lugar, p.responsable, p.lote, p.vencimiento
from p
left join core.productos prd on prd.codigo = p.producto_bulto::text;

revoke all on calc.produccion_kg from anon, authenticated;

-- 2. Producido (sin costos).
create or replace view public.reporte_produccion as
select fecha, semana, mes, producto_codigo, producto, familia,
       case when es_produccion then 'Producción'
            when unidad_cantidad = 'armado' then 'Armado'
            else tipo end                                        as clase,
       bultos, kilos, scrap_producto, scrap_flexible, masas_declaradas,
       lugar, responsable, lote, vencimiento
from calc.produccion_kg;

-- 3. Plan contra real por semana y producto (solo produccion nueva).
create or replace view public.reporte_plan_vs_real as
with plan as (
  select date_trunc('week', pl.fecha)::date as semana, pl.producto_codigo,
         max(pl.producto) as producto_plan,
         sum(pl.bultos) as bultos_plan,
         sum(coalesce(pl.kilos, pl.bultos * prd.kg_por)) as kilos_plan
  from core.plan_produccion pl
  left join core.productos prd on prd.codigo = pl.producto_codigo::text
  where pl.fecha >= date '2025-03-01' and pl.bultos > 0
  group by 1, 2
), real as (
  select semana, producto_codigo, max(producto) as producto_real, max(familia) as familia,
         sum(bultos) as bultos_real, sum(kilos) as kilos_real
  from calc.produccion_kg
  where es_produccion
  group by 1, 2
)
select coalesce(pl.semana, r.semana)                              as semana,
       coalesce(pl.producto_codigo, r.producto_codigo)            as producto_codigo,
       coalesce(prd.producto, r.producto_real, pl.producto_plan)  as producto,
       coalesce(prd.familia, r.familia, 'SIN CLASIFICAR')         as familia,
       coalesce(pl.bultos_plan, 0)                                as bultos_plan,
       coalesce(r.bultos_real, 0)                                 as bultos_real,
       round(coalesce(pl.kilos_plan, 0), 1)                       as kilos_plan,
       round(coalesce(r.kilos_real, 0), 1)                        as kilos_real,
       case when pl.semana is null then 'Fuera de plan'
            when coalesce(r.bultos_real, 0) = 0 then 'No se hizo'
            when r.bultos_real < 0.9 * pl.bultos_plan then 'Menos que el plan'
            when r.bultos_real > 1.1 * pl.bultos_plan then 'Más que el plan'
            else 'Cumplido' end                                   as resultado,
       coalesce(pl.semana, r.semana) + 6 < current_date           as semana_cerrada
from plan pl
full join real r on r.semana = pl.semana and r.producto_codigo = pl.producto_codigo
left join core.productos prd on prd.codigo = coalesce(pl.producto_codigo, r.producto_codigo)::text;

-- 4. Masas y scrap de masa.
create or replace view public.reporte_masas as
select fecha::date as fecha,
       date_trunc('week', fecha)::date  as semana,
       date_trunc('month', fecha)::date as mes,
       masa_codigo, masa, masas, coalesce(scrap_kg, 0) as scrap_kg, observaciones
from core.produccion_masas
where fecha >= date '2025-03-01';

-- 5. Stock de PT por lote, con vencimiento y dias de venta (ventas de los ultimos 90 dias).
create or replace view public.reporte_stock_pt as
with venta as (
  select ltrim(producto_codigo, '0') as producto_codigo, sum(kilos) / 90.0 as kilos_dia
  from rpt.ventas_analisis
  where fecha > current_date - 90 and producto_codigo ~ '^[0-9]+$'
  group by 1
), tot as (
  select producto_codigo, sum(kilos) as kilos_producto from core.stock_pt where bultos > 0 group by 1
)
select s.deposito, s.producto_codigo,
       coalesce(prd.producto, s.producto)                         as producto,
       coalesce(prd.familia, 'SIN CLASIFICAR')                    as familia,
       s.vencimiento, s.bultos, s.kilos,
       s.vencimiento - current_date                               as dias_a_vencer,
       case when s.vencimiento is null then 'Sin fecha'
            when s.vencimiento < current_date then 'Vencido'
            when s.vencimiento < current_date + 30 then 'Vence en < 30 días'
            when s.vencimiento < current_date + 60 then 'Vence en 30-60 días'
            else 'OK' end                                         as estado_vencimiento,
       round(v.kilos_dia, 1)                                      as venta_kg_dia,
       round(t.kilos_producto / nullif(v.kilos_dia, 0))           as dias_de_venta_producto
from core.stock_pt s
left join core.productos prd on prd.codigo = s.producto_codigo::text
left join venta v on v.producto_codigo = s.producto_codigo::text
left join tot t on t.producto_codigo = s.producto_codigo
where s.bultos > 0;

-- 6. Producido valorizado (solo direccion). Costo del mes; si el mes no tiene, el ultimo anterior.
create or replace view public.reporte_produccion_costo as
select p.fecha, p.semana, p.mes, p.producto_codigo, p.producto, p.familia, p.es_produccion,
       p.bultos, p.kilos, p.scrap_producto,
       c.costo_kg,
       round(p.kilos * c.costo_kg, 2) as valor_producido
from calc.produccion_kg p
left join lateral (
  select ca.costo_kg from core.costos_articulos ca
  where ca.articulo_codigo = lpad(p.producto_codigo::text, 7, '0') and ca.mes <= p.mes
  order by ca.mes desc limit 1
) c on true;

revoke all on public.reporte_produccion, public.reporte_plan_vs_real, public.reporte_masas,
  public.reporte_stock_pt, public.reporte_produccion_costo from anon, authenticated, public;
grant select on public.reporte_produccion, public.reporte_plan_vs_real, public.reporte_masas,
  public.reporte_stock_pt, public.reporte_produccion_costo to looker_lectura;

-- 7. Control.
select 'partes desde 03/2025' as que, count(*)::text as valor from calc.produccion_kg
union all select 'partes sin kg (producto sin peso en el maestro)', count(*)::text
  from calc.produccion_kg where es_produccion and kilos is null
union all select * from (
  select 'sin kg: ' || producto_codigo || ' ' || coalesce(producto, ''), count(*)::text
  from calc.produccion_kg where es_produccion and kilos is null group by producto_codigo, producto
  order by count(*) desc limit 10) x
union all select * from (
  select 'kg producidos ' || to_char(mes, 'YYYY-MM'), round(sum(kilos))::text
  from calc.produccion_kg where es_produccion and mes >= date_trunc('month', current_date) - interval '5 months'
  group by mes order by mes) y
union all select * from (
  select 'plan vs real semana ' || semana || ': ' || resultado, count(*)::text
  from public.reporte_plan_vs_real where semana = (select max(semana) from public.reporte_plan_vs_real where semana_cerrada)
  group by semana, resultado) z
union all select 'lotes de PT vencidos', count(*)::text from public.reporte_stock_pt where estado_vencimiento = 'Vencido'
union all select 'acciones en el plan: ' || coalesce(accion, '(vacío)'), count(*)::text
  from core.plan_produccion where fecha >= current_date - 60 group by accion;
