-- 013_hojas_escalonar.sql
-- Primera corrida (28/10/2026): 15 de 19 pestañas OK; el resto fallo al arrancar la funcion
-- (503 BOOT_ERROR) porque se disparaban las 19 llamadas al mismo tiempo.
-- Cambio: cada 5 minutos se mandan a leer como maximo 4 pestañas, empezando por las que hace mas
-- tiempo que no se leen (o que fallaron). Cada pestaña se sigue leyendo cada 30 minutos.
-- Se puede volver a ejecutar sin riesgo.

drop function if exists hojas.disparar();

create or replace function hojas.disparar(p_max int default 4)
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
    order by ultima_lectura nulls first, fuente
    limit greatest(p_max, 1)
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

revoke all on function hojas.disparar(int) from public, anon, authenticated;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'leer_hojas';
  perform cron.schedule('leer_hojas', '*/5 * * * *', 'select hojas.disparar()');
end $$;

-- Control: que pestañas faltan leer.
select fuente, hoja, filas, ultimo_error from hojas.estado where filas = 0 or ultimo_error is not null;
