-- 048_fichadas_reloj.sql
-- Marcas del reloj facial (Asistencia Anual.xlsx, hoja "Hoja1"), acumulado del año. Se exporta a mano
-- y se sube como NUEVA VERSION del mismo archivo en Drive (Administrar versiones), asi el ID no cambia.
-- Las vistas que lo usan (core.fichadas, calc.asistencia_dia, reportes) estan en la 047.
-- Correr DESPUES de la 047. Se puede volver a ejecutar sin riesgo.

insert into hojas.fuentes (fuente, planilla_id, hoja, tipo, descripcion, cada_minutos) values
  ('fichadas', '1yYROW658JPp6VW0eGV4DGGbVb9-ShknA', 'Hoja1', 'xlsx',
   'Marcas del reloj facial (export manual, acumulado del año)', 360)
on conflict (fuente) do update set planilla_id = excluded.planilla_id, hoja = excluded.hoja, tipo = excluded.tipo,
  descripcion = excluded.descripcion, cada_minutos = excluded.cada_minutos;

insert into hojas.encabezados (fuente, fila_encabezado) values ('fichadas', 1)
on conflict (fuente) do update set fila_encabezado = excluded.fila_encabezado;

select hojas.disparar();

-- Control (la lectura tarda 1-2 minutos: si da 0, volver a correr desde aca).
select 'marcas leidas' as que, count(*)::text as valor from core.fichadas
union all select 'personas', count(distinct id_reloj)::text from core.fichadas
union all select 'desde / hasta', min(fecha) || ' / ' || max(fecha) from core.fichadas
union all select 'personas sin maestro', count(distinct a.id_reloj)::text
  from calc.asistencia_dia a where a.rol = 'Sin maestro'
union all select 'error de lectura', coalesce(ultimo_error, 'ninguno') from hojas.fuentes where fuente = 'fichadas';
