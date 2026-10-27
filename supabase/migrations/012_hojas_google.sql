-- 012_hojas_google.sql
-- Lectura automatica de las planillas de Google (insumos, produccion, pedidos) hacia Supabase.
-- Opcion B elegida por Cuci el 27/10/2026: Supabase lee directo de Google con una cuenta de servicio.
--
--   pg_cron (cada 30 min) -> hojas.disparar() -> pg_net llama a la Edge Function happyfood-sync-hojas
--   una vez por pestaña -> la funcion lee la pestaña con la API de Google -> hojas.cargar() guarda
--   la foto completa en hojas.filas (solo si cambio). Cada lectura queda en hojas.lecturas.
--   hojas.control_salud() avisa a Healthchecks si alguna pestaña no se pudo leer.
--
-- Las planillas NO se modifican: la cuenta de servicio tiene permiso de lectura.
-- Requisitos (ver insumos/PASO_A_PASO_GOOGLE.md): extension pg_net, secretos en Vault
--   'happyfood_cron_key' (clave secreta de Supabase) y opcional 'hc_hojas_url' (Healthchecks).
-- Se puede volver a ejecutar sin riesgo.

create extension if not exists pg_net;
create schema if not exists hojas;

-- 1. Pestañas a leer. Sumar una = insertar una fila.
create table if not exists hojas.fuentes (
  fuente          text primary key check (fuente ~ '^[a-z0-9_]{1,40}$'),
  planilla_id     text not null,
  hoja            text not null,
  tipo            text not null default 'sheet' check (tipo in ('sheet','xlsx')),
  descripcion     text not null,
  cada_minutos    int  not null default 30 check (cada_minutos >= 30),
  activa          boolean not null default true,
  ultimo_hash     text,
  ultima_lectura  timestamptz,
  ultimo_cambio   timestamptz,
  ultimo_error    text
);

-- 2. Foto de cada pestaña: una fila de la planilla = una fila acá (valores como arreglo JSON).
create table if not exists hojas.filas (
  fuente  text not null references hojas.fuentes(fuente) on delete cascade,
  fila    int  not null,            -- numero de fila en la planilla (1 = primera)
  valores jsonb not null,           -- ["A","B",...] tal cual se ven en la planilla
  primary key (fuente, fila)
);

-- 3. Historial de lecturas.
create table if not exists hojas.lecturas (
  id      bigint generated always as identity primary key,
  fuente  text not null,
  fecha   timestamptz not null default now(),
  ok      boolean not null,
  filas   int,
  cambio  boolean,
  error   text
);
create index if not exists lecturas_fuente_fecha_idx on hojas.lecturas (fuente, fecha desc);

alter table hojas.fuentes  enable row level security;
alter table hojas.filas    enable row level security;
alter table hojas.lecturas enable row level security;
revoke all on all tables in schema hojas from anon, authenticated;

-- 4. Guardar una lectura (la llama la Edge Function).
create or replace function hojas.cargar(p_fuente text, p_hash text, p_filas jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_hash_ant text;
  v_n int;
begin
  select f.ultimo_hash into v_hash_ant from hojas.fuentes f where f.fuente = p_fuente and f.activa;
  if not found then raise exception 'Fuente no habilitada'; end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then raise exception 'Formato invalido'; end if;
  v_n := jsonb_array_length(p_filas);

  if v_hash_ant is not distinct from p_hash then
    update hojas.fuentes set ultima_lectura = now(), ultimo_error = null where fuente = p_fuente;
    insert into hojas.lecturas (fuente, ok, filas, cambio) values (p_fuente, true, v_n, false);
    return jsonb_build_object('ok', true, 'fuente', p_fuente, 'filas', v_n, 'cambio', false);
  end if;

  delete from hojas.filas where fuente = p_fuente;
  insert into hojas.filas (fuente, fila, valores)
  select p_fuente, (e.n)::int, e.v
  from jsonb_array_elements(p_filas) with ordinality as e(v, n)
  where jsonb_typeof(e.v) = 'array';

  update hojas.fuentes
     set ultimo_hash = p_hash, ultima_lectura = now(), ultimo_cambio = now(), ultimo_error = null
   where fuente = p_fuente;
  insert into hojas.lecturas (fuente, ok, filas, cambio) values (p_fuente, true, v_n, true);
  return jsonb_build_object('ok', true, 'fuente', p_fuente, 'filas', v_n, 'cambio', true);
end $$;

create or replace function hojas.registrar_error(p_fuente text, p_error text)
returns void
language sql
security definer
set search_path to ''
as $$
  update hojas.fuentes set ultimo_error = left(p_error, 500) where fuente = p_fuente;
  insert into hojas.lecturas (fuente, ok, error) values (p_fuente, false, left(p_error, 500));
$$;

revoke all on function hojas.cargar(text, text, jsonb), hojas.registrar_error(text, text)
  from public, anon, authenticated;

-- 5. Disparo: una llamada a la Edge Function por pestaña que toque leer.
create or replace function hojas.disparar()
returns int
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_clave text;
  v_n int := 0;
  f record;
begin
  select decrypted_secret into v_clave from vault.decrypted_secrets where name = 'happyfood_cron_key';
  if v_clave is null then raise exception 'Falta el secreto happyfood_cron_key en Vault'; end if;

  for f in
    select fuente from hojas.fuentes
    where activa
      and (ultima_lectura is null or ultima_lectura < now() - make_interval(mins => cada_minutos - 5))
  loop
    perform net.http_post(
      url     := 'https://igcewbadhejtesbogewm.supabase.co/functions/v1/happyfood-sync-hojas',
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_clave),
      body    := jsonb_build_object('accion', 'leer', 'fuente', f.fuente),
      timeout_milliseconds := 120000
    );
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- 6. Control: si alguna pestaña activa no se leyo bien en la ultima hora, avisa a Healthchecks.
create or replace function hojas.control_salud()
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_url text;
  v_malas text;
begin
  select string_agg(fuente, ', ' order by fuente) into v_malas
  from hojas.fuentes
  where activa
    and (ultima_lectura is null
         or ultima_lectura < now() - make_interval(mins => cada_minutos + 35)
         or ultimo_error is not null);

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'hc_hojas_url';
  if v_url is not null then
    perform net.http_get(url := v_url || case when v_malas is null then '' else '/fail' end);
  end if;
  return coalesce('Con problemas: ' || v_malas, 'Todo OK');
end $$;

revoke all on function hojas.disparar(), hojas.control_salud() from public, anon, authenticated;

-- 7. Estado legible.
create or replace view hojas.estado as
select f.fuente, f.descripcion, f.hoja, f.activa,
       (select count(*) from hojas.filas x where x.fuente = f.fuente) as filas,
       f.ultima_lectura at time zone 'America/Argentina/Cordoba' as ultima_lectura,
       f.ultimo_cambio  at time zone 'America/Argentina/Cordoba' as ultimo_cambio,
       f.ultimo_error
from hojas.fuentes f
order by f.fuente;

-- 8. Pestañas (IDs tomados de docs/traspaso_stock_insumos.md y docs/traspaso_tablero_produccion.md).
insert into hojas.fuentes (fuente, planilla_id, hoja, tipo, descripcion, cada_minutos) values
  ('conteo_stock',        '1hF4u7DKpaoNTH4y9Elo9kE4oNjNjHVpOmZh_saJ9lU8', 'ConteoStock', 'sheet', 'Conteo semanal de materias primas y envases', 30),
  ('compras_insumos',     '1RfFVytTdq_UyaIvVn-JoL3nYO391gaxRPPGyVWTOcjU', 'INSUMOS', 'sheet', 'Compras: maestro de insumos (nombre, unidad)', 30),
  ('compras_oc',          '1RfFVytTdq_UyaIvVn-JoL3nYO391gaxRPPGyVWTOcjU', 'OC_DETALLE', 'sheet', 'Compras: ordenes de compra y recepciones', 30),
  ('compras_prov_alim',   '1RfFVytTdq_UyaIvVn-JoL3nYO391gaxRPPGyVWTOcjU', 'INSUMOS_PROV_ALIM', 'sheet', 'Compras: insumo-proveedor alimenticios', 30),
  ('compras_prov_noalim', '1RfFVytTdq_UyaIvVn-JoL3nYO391gaxRPPGyVWTOcjU', 'INSUMOS_PROV_NOALIM', 'sheet', 'Compras: insumo-proveedor no alimenticios', 30),
  ('produccion_partes',   '1CZEC7YuURKd6JJKRHyXquVYY-ETB_DOEUT148EqawGA', 'Producción', 'sheet', 'Parte diario de producto terminado', 30),
  ('produccion_masas',    '1CZEC7YuURKd6JJKRHyXquVYY-ETB_DOEUT148EqawGA', 'Producción_Masas', 'sheet', 'Declaracion de masas', 30),
  ('plan_semanal',        '1bmctylGk4K99Nc4e6s4kujyd-ztzbLR6ruzaLa701zs', 'Plan de producción Semanal', 'sheet', 'Plan de produccion semanal', 30),
  ('pedidos_pend_kg',     '1T1WdLnR6UTDRnlHLf57xYK8twYQ-e1AWODicytga2UY', 'KG', 'sheet', 'Reporte de pedidos pendientes: envases por producto', 30),
  ('stock_pt_cd',         '1Kv0DQjxqwH2zkEiKg1Izp1t-Jl2zuac2xi4ExRKcmQY', 'STOCK CD', 'sheet', 'Stock de producto terminado: centro de distribucion', 30),
  ('stock_pt_planta',     '1Kv0DQjxqwH2zkEiKg1Izp1t-Jl2zuac2xi4ExRKcmQY', 'STOCK PLANTA', 'sheet', 'Stock de producto terminado: planta', 30),
  ('stock_pt_transito',   '1Kv0DQjxqwH2zkEiKg1Izp1t-Jl2zuac2xi4ExRKcmQY', 'STOCK TRANSITO', 'sheet', 'Stock de producto terminado: en transito', 30),
  ('pedidos_ordenes',     '1Sr_ep7G2cpRSeH3YNMm0lzaFlHGuMk8Mio6qHb3Le_Q', 'ORDENES', 'sheet', 'Pedidos: cabecera', 30),
  ('pedidos_detalle',     '1Sr_ep7G2cpRSeH3YNMm0lzaFlHGuMk8Mio6qHb3Le_Q', 'DETALLE', 'sheet', 'Pedidos: lineas', 30),
  ('pedidos_productos',   '1Sr_ep7G2cpRSeH3YNMm0lzaFlHGuMk8Mio6qHb3Le_Q', 'PRODUCTOS', 'sheet', 'Pedidos: maestro de productos', 30),
  ('recetas',             '1sd7nyXZjGsot2TE91553eYVwPXCfoNbY', 'Recetas', 'xlsx', 'Recetas oficiales (17 productos)', 360),
  ('recetas_kg_producto', '1sd7nyXZjGsot2TE91553eYVwPXCfoNbY', 'Maestro Kg x Producto', 'xlsx', 'Kg por producto', 360),
  ('envases_flx',         '1sd7nyXZjGsot2TE91553eYVwPXCfoNbY', 'StkEnvasesFlx', 'xlsx', 'Envases y flexibles', 360),
  ('insumos_activos',     '1sd7nyXZjGsot2TE91553eYVwPXCfoNbY', 'Control Stock en Dias', 'xlsx', 'Marca Activo/Inactivo de insumos (col AK)', 360)
on conflict (fuente) do update set
  planilla_id = excluded.planilla_id, hoja = excluded.hoja, tipo = excluded.tipo,
  descripcion = excluded.descripcion, cada_minutos = excluded.cada_minutos;

-- 9. Programacion: leer cada 30 minutos; controlar a los :20 y :50.
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('leer_hojas', 'control_hojas');
  perform cron.schedule('leer_hojas',    '*/30 * * * *', 'select hojas.disparar()');
  perform cron.schedule('control_hojas', '20,50 * * * *', 'select hojas.control_salud()');
end $$;
