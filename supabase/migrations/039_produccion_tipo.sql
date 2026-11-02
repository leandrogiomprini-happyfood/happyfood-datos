-- 039_produccion_tipo.sql
-- Cuci (01/11/2026): el informe tiene que diferenciar el tipo de producto de la columna G del parte
-- ("Tipo de Producto"): Super, Distri, Semielaborado, Rearmado, Retrabajo.
--   * clase pasa a mostrar ese tipo tal cual (antes: "Producción" / "Armado" / tipo).
--   * nueva columna cuenta_como_produccion (Sí/No): Super, Distri y Semielaborado suman kg producidos;
--     Rearmado y Retrabajo no (son producto ya elaborado que se rearma o se reprocesa: no es kg nuevo).
-- En Looker: el filtro de "clase" que tenia "Producción" hay que cambiarlo por cuenta_como_produccion = Sí.
-- Se puede volver a ejecutar sin riesgo.

create or replace view public.reporte_produccion as
select fecha, semana, mes, producto_codigo, producto, familia,
       case when tipo = '' then 'Sin tipo' else tipo end            as clase,
       bultos, kilos, scrap_producto, scrap_flexible, masas_declaradas,
       lugar, responsable, lote, vencimiento,
       case when es_produccion then 'Sí' else 'No' end               as cuenta_como_produccion
from calc.produccion_kg;

-- Control: partes, bultos y kg por tipo en los ultimos 3 meses.
select clase, cuenta_como_produccion, count(*) as partes, round(sum(bultos)) as bultos, round(sum(kilos)) as kilos
from public.reporte_produccion
where fecha >= date_trunc('month', current_date) - interval '2 months'
group by 1, 2
order by 2 desc, 5 desc nulls last;
