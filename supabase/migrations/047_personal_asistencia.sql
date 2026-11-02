-- 047_personal_asistencia.sql
-- Personal y asistencia (pedido de Cuci, 02/11/2026). Objetivos: presentismo, dotacion por dia
-- cruzada con produccion, quien vino y su rol, y horas extra aproximadas.
-- Fuentes (Google Drive, compartidas como Lector con la cuenta de servicio):
--   personal_maestro  hoja "Personal" del maestro que completa Cuci (ID reloj, nombre, rol, sector,
--                     cuenta para produccion, activo, fecha de egreso, Asistencia: Diaria / A demanda)
--   fichadas          export del reloj facial (xlsx, hoja "Hoja1"), acumulado del año. Se exporta a
--                     mano y se sube como NUEVA VERSION del mismo archivo (asi no cambia el ID).
-- Reglas de las marcas (el reloj no dice si es entrada o salida, todas dicen "In"):
--   * dos marcas de la misma persona con menos de 5 minutos se cuentan como una;
--   * vino = al menos una marca ese dia;
--   * 2 marcas: entrada y salida; 4 marcas: entrada, salida al descanso, vuelta, salida;
--     1, 3 o 5+ marcas: dia "incompleto" (vino, pero sin horas);
--   * horas_en_planta = primera a ultima marca (con descanso, como la planilla de octubre);
--     horas_sin_descanso = sin el descanso (solo dias con 4 marcas);
--   * horas teoricas: 8 de lunes a viernes, 4 el sabado; extra_aprox = horas en planta por encima
--     de las teoricas (es tiempo dentro de la planta, no horas extra autorizadas).
-- Los IDs de las dos planillas van en la seccion 1. Se puede volver a ejecutar sin riesgo.

set statement_timeout = '10min';

-- 1. Planillas (IDs de Drive) y fila de encabezado.
insert into hojas.fuentes (fuente, planilla_id, hoja, tipo, descripcion, cada_minutos) values
  ('personal_maestro', 'ID_MAESTRO', 'Personal', 'sheet', 'Maestro de personal: rol, sector, cuenta para produccion', 360),
  ('fichadas',         'ID_FICHADAS', 'Hoja1', 'xlsx', 'Marcas del reloj facial (export manual, acumulado del año)', 360)
on conflict (fuente) do update set planilla_id = excluded.planilla_id, hoja = excluded.hoja, tipo = excluded.tipo,
  descripcion = excluded.descripcion, cada_minutos = excluded.cada_minutos;

insert into hojas.encabezados (fuente, fila_encabezado) values ('personal_maestro', 1), ('fichadas', 1)
on conflict (fuente) do update set fila_encabezado = excluded.fila_encabezado;

-- Fecha en texto: dd/mm/aaaa (planilla) o aaaa-mm-dd (export del reloj).
create or replace function hojas.fecha_hora(v jsonb)
returns timestamp
language plpgsql
immutable
as $$
declare
  t text;
  m text[];
begin
  if v is null or jsonb_typeof(v) <> 'string' then return null; end if;
  t := btrim(v #>> '{}');
  m := regexp_match(t, '^(\d{4})-(\d{1,2})-(\d{1,2})[ T]?(\d{1,2})?:?(\d{2})?:?(\d{2})?');
  if m is not null then
    return make_timestamp(m[1]::int, m[2]::int, m[3]::int,
                          coalesce(m[4], '0')::int, coalesce(m[5], '0')::int, coalesce(m[6], '0')::int);
  end if;
  m := regexp_match(t, '^(\d{1,2})/(\d{1,2})/(\d{4})\s*(\d{1,2})?:?(\d{2})?:?(\d{2})?');
  if m is not null then
    return make_timestamp(m[3]::int, m[2]::int, m[1]::int,
                          coalesce(m[4], '0')::int, coalesce(m[5], '0')::int, coalesce(m[6], '0')::int);
  end if;
  return null;
exception when others then
  return null;
end $$;

-- 2. Maestro de personal.
create or replace view core.personal as
select hojas.txt(datos -> 'ID reloj')                                   as id_reloj,
       hojas.txt(datos -> 'Nombre en el reloj')                         as nombre_reloj,
       coalesce(hojas.txt(datos -> 'Nombre completo'), hojas.txt(datos -> 'Nombre en el reloj')) as nombre,
       coalesce(hojas.txt(datos -> 'Rol'), 'Sin rol')                   as rol,
       hojas.txt(datos -> 'Sector')                                     as sector,
       lower(coalesce(hojas.txt(datos -> 'Cuenta para producción'), '')) in ('sí', 'si', 's')   as cuenta_produccion,
       lower(coalesce(hojas.txt(datos -> 'Activo'), 'sí')) not in ('no', 'n')                    as activo,
       hojas.fecha_hora(datos -> 'Fecha de egreso')::date               as fecha_egreso,
       hojas.txt(datos -> 'Comentario')                                 as comentario,
       coalesce(lower(hojas.txt(datos -> 'Asistencia')), 'diaria') like '%demanda%' as a_demanda
from hojas.tabla
where fuente = 'personal_maestro' and hojas.txt(datos -> 'ID reloj') is not null;

-- 3. Marcas del reloj (sin las repetidas a menos de 5 minutos).
create or replace view core.fichadas as
with m as (
  select hojas.txt(datos -> 'ID de usuario')          as id_reloj,
         hojas.txt(datos -> 'Nombre')                 as nombre_reloj,
         hojas.fecha_hora(datos -> 'Fecha/Hora')      as marca
  from hojas.tabla
  where fuente = 'fichadas'
), o as (
  select m.*, lag(marca) over (partition by id_reloj, marca::date order by marca) as anterior
  from m
  where marca is not null and id_reloj is not null
)
select id_reloj, nombre_reloj, marca, marca::date as fecha
from o
where anterior is null or marca - anterior >= interval '5 minutes';

-- 4. Un renglon por persona y dia.
create or replace view calc.asistencia_dia as
with n as (
  select f.*, row_number() over (partition by id_reloj, fecha order by marca) as nro,
         count(*) over (partition by id_reloj, fecha) as marcas
  from core.fichadas f
), d as (
  select id_reloj, max(nombre_reloj) as nombre_reloj, fecha, max(marcas) as marcas,
         min(marca) as primera, max(marca) as ultima,
         max(marca) filter (where nro = 2) as m2, max(marca) filter (where nro = 3) as m3
  from n
  group by id_reloj, fecha
)
select d.fecha,
       date_trunc('week', d.fecha)::date  as semana,
       date_trunc('month', d.fecha)::date as mes,
       extract(isodow from d.fecha)::int  as dia_semana,
       d.id_reloj,
       coalesce(p.nombre, d.nombre_reloj) as nombre,
       coalesce(p.rol, 'Sin maestro')     as rol,
       coalesce(p.cuenta_produccion, false) as cuenta_produccion,
       d.marcas,
       case when d.marcas in (2, 4) then 'completo' else 'incompleto' end as estado_marcas,
       d.primera::time as entrada,
       d.ultima::time  as salida,
       case when d.marcas in (2, 4) then round(extract(epoch from d.ultima - d.primera) / 3600.0, 2) end
         as horas_en_planta,
       case when d.marcas = 4 then round(extract(epoch from d.m3 - d.m2) / 60.0) end as minutos_descanso,
       case when d.marcas = 4 then round(extract(epoch from (d.ultima - d.primera) - (d.m3 - d.m2)) / 3600.0, 2)
            when d.marcas = 2 then round(extract(epoch from d.ultima - d.primera) / 3600.0, 2) end
         as horas_sin_descanso,
       case when extract(isodow from d.fecha) = 6 then 4 else 8 end as horas_teoricas,
       case when d.marcas in (2, 4)
            then round(greatest(extract(epoch from d.ultima - d.primera) / 3600.0
                                - case when extract(isodow from d.fecha) = 6 then 4 else 8 end, 0), 2) end
         as extra_aprox
from d
left join core.personal p on p.id_reloj = d.id_reloj;

-- 5. Reportes.
-- 5a. Asistencia por persona y dia.
create or replace view public.reporte_asistencia as
select a.*, case when a.extra_aprox >= 0.5 then 'Sí' else 'No' end as extra_mas_de_30_min
from calc.asistencia_dia a;

-- 5b. Ausencias: dias habiles de la planta (con al menos 3 personas) en que una persona activa no marco.
--     Quien tiene Asistencia = "A demanda" en el maestro (centro de distribucion que viene a dar soporte)
--     no genera ausencias; cuando viene, suma en la dotacion como cualquiera.
create or replace view public.reporte_ausencias as
with habiles as (
  select fecha from core.fichadas group by fecha having count(distinct id_reloj) >= 3
), rango as (
  select p.id_reloj, p.nombre, p.rol, p.cuenta_produccion,
         min(f.fecha) as alta, coalesce(p.fecha_egreso, max(f.fecha)) as baja
  from core.personal p
  join core.fichadas f on f.id_reloj = p.id_reloj
  where not p.a_demanda
  group by p.id_reloj, p.nombre, p.rol, p.cuenta_produccion, p.fecha_egreso
)
select h.fecha, date_trunc('month', h.fecha)::date as mes, extract(isodow from h.fecha)::int as dia_semana,
       r.id_reloj, r.nombre, r.rol, r.cuenta_produccion,
       exists (select 1 from core.fichadas f where f.id_reloj = r.id_reloj and f.fecha = h.fecha) as presente
from habiles h
join rango r on h.fecha between r.alta and r.baja;

-- 5c. Dotacion por dia cruzada con produccion (kg de reporte_produccion_dia, 041-043).
create or replace view public.reporte_dotacion_dia as
with dot as (
  select fecha,
         count(*)                                         as presentes,
         count(*) filter (where cuenta_produccion)        as presentes_produccion,
         sum(horas_en_planta) filter (where cuenta_produccion) as horas_produccion,
         count(*) filter (where cuenta_produccion and estado_marcas = 'incompleto') as marcas_incompletas,
         sum(extra_aprox) filter (where cuenta_produccion) as extra_aprox_produccion
  from calc.asistencia_dia
  group by fecha
)
select d.fecha,
       date_trunc('week', d.fecha)::date  as semana,
       date_trunc('month', d.fecha)::date as mes,
       extract(isodow from d.fecha)::int  as dia_semana,
       d.presentes, d.presentes_produccion,
       round(d.horas_produccion, 1)       as horas_produccion,
       d.marcas_incompletas,
       round(d.extra_aprox_produccion, 1) as extra_aprox_produccion,
       coalesce(p.kilos_produccion, 0)    as kilos_produccion,
       coalesce(p.bultos_rearmado, 0)     as bultos_rearmado,
       p.nivel_dia,
       round(p.kilos_produccion / nullif(d.presentes_produccion, 0), 1) as kilos_por_persona,
       round(p.kilos_produccion / nullif(d.presentes_produccion * case when extract(isodow from d.fecha) = 6 then 4 else 8 end, 0), 1)
         as kilos_por_hora_persona
from dot d
left join public.reporte_produccion_dia p on p.fecha = d.fecha;

revoke all on core.personal, core.fichadas, calc.asistencia_dia from anon, authenticated;
revoke all on public.reporte_asistencia, public.reporte_ausencias, public.reporte_dotacion_dia
  from anon, authenticated, public;
grant select on public.reporte_asistencia, public.reporte_ausencias, public.reporte_dotacion_dia to looker_lectura;
