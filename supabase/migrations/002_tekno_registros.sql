-- 002_tekno_registros.sql
-- Tabla generica para sumar tablas de Tekno sin cambiar codigo, y su funcion de carga.
-- NO toca tekno.ventas, tekno.ventas_detalle ni tekno.sincronizar_lote: las ventas
-- siguen por el camino actual. Se puede volver a ejecutar sin riesgo.

-- 1. Tablas que el servidor tiene permitido enviar. Sumar una tabla = insertar una fila.
create table if not exists tekno.tablas_permitidas (
  tabla        text primary key check (tabla ~ '^[a-z0-9_]{1,40}$'),
  archivo_dbf  text not null,
  descripcion  text not null,
  activa       boolean not null default true,
  creada       timestamptz not null default now()
);

-- 2. Copia cruda de cualquier tabla de Tekno (mismo formato que tekno.ventas).
create table if not exists tekno.registros (
  tabla                text not null references tekno.tablas_permitidas(tabla),
  registro_origen      integer not null check (registro_origen > 0),
  datos                jsonb not null,
  eliminado_origen     boolean not null,
  fecha_sincronizacion timestamptz not null default now(),
  primary key (tabla, registro_origen)
);

create index if not exists registros_tabla_fecha_idx
  on tekno.registros (tabla, fecha_sincronizacion);

-- Solo la funcion (SECURITY DEFINER) y el rol postgres escriben; la API publica no ve nada.
alter table tekno.tablas_permitidas enable row level security;
alter table tekno.registros enable row level security;
revoke all on tekno.tablas_permitidas, tekno.registros from anon, authenticated;

-- 3. Carga de un lote (1 a 100 registros), con las mismas validaciones que sincronizar_lote.
create or replace function tekno.sincronizar_registros(p_tabla text, p_registros jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_registro   jsonb;
  v_id         integer;
  v_ids        integer[] := array[]::integer[];
  v_procesados integer;
  v_cambiados  integer;
begin
  if p_tabla is null or not exists (
    select 1 from tekno.tablas_permitidas t where t.tabla = p_tabla and t.activa
  ) then
    raise exception 'Tabla no permitida';
  end if;

  if p_registros is null
     or jsonb_typeof(p_registros) <> 'array'
     or jsonb_array_length(p_registros) not between 1 and 100 then
    raise exception 'Lote invalido';
  end if;

  -- Validar todo el lote antes de escribir.
  for v_registro in select value from jsonb_array_elements(p_registros) loop
    if jsonb_typeof(v_registro) <> 'object'
       or jsonb_typeof(v_registro->'registro_origen') <> 'number'
       or (v_registro->>'registro_origen') !~ '^[0-9]+$'
       or jsonb_typeof(v_registro->'datos') <> 'object'
       or jsonb_typeof(v_registro->'eliminado_origen') <> 'boolean' then
      raise exception 'Registro invalido';
    end if;
    v_id := (v_registro->>'registro_origen')::integer;
    if v_id < 1 or v_id = any(v_ids) then
      raise exception 'Identificador invalido o duplicado';
    end if;
    v_ids := array_append(v_ids, v_id);
  end loop;

  v_procesados := jsonb_array_length(p_registros);

  -- Insertar o actualizar; solo toca la fila si algo cambio.
  with entrada as (
    select (e->>'registro_origen')::integer   as registro_origen,
           e->'datos'                         as datos,
           (e->>'eliminado_origen')::boolean  as eliminado_origen
    from jsonb_array_elements(p_registros) e
  ), escritos as (
    insert into tekno.registros as r (tabla, registro_origen, datos, eliminado_origen)
    select p_tabla, registro_origen, datos, eliminado_origen from entrada
    on conflict (tabla, registro_origen) do update
      set datos = excluded.datos,
          eliminado_origen = excluded.eliminado_origen,
          fecha_sincronizacion = now()
      where r.datos is distinct from excluded.datos
         or r.eliminado_origen is distinct from excluded.eliminado_origen
    returning 1
  )
  select count(*) into v_cambiados from escritos;

  return jsonb_build_object(
    'ok', true,
    'tabla', p_tabla,
    'procesados', v_procesados,
    'cambiados', v_cambiados
  );
end;
$function$;

revoke all on function tekno.sincronizar_registros(text, jsonb) from public, anon, authenticated;

-- 4. Tablas de la fase 1 (ver docs/tekno_tablas.md).
insert into tekno.tablas_permitidas (tabla, archivo_dbf, descripcion) values
  ('tablcomp', 'TABLCOMP.DBF', 'Tipos de comprobante y codigo AFIP'),
  ('tablvend', 'TABLVEND.DBF', 'Vendedores'),
  ('tabllist', 'TABLLIST.DBF', 'Listas de precios'),
  ('tablfopa', 'TABLFOPA.DBF', 'Formas de pago'),
  ('tablrubr', 'TABLRUBR.DBF', 'Rubros de compras'),
  ('tablsifi', 'TABLSIFI.DBF', 'Condiciones fiscales'),
  ('tabltran', 'TABLTRAN.DBF', 'Transportes'),
  ('tablimpu', 'TABLIMPU.DBF', 'Impuestos'),
  ('maescuen', 'MAESCUEN.DBF', 'Plan de cuentas'),
  ('maesclie', 'MAESCLIE.DBF', 'Clientes'),
  ('maesprov', 'MAESPROV.DBF', 'Proveedores'),
  ('maesarti', 'MAESARTI.DBF', 'Articulos'),
  ('maesprec', 'MAESPREC.DBF', 'Precios por articulo y lista'),
  ('obsevent', 'OBSEVENT.DBF', 'Observaciones de comprobantes de venta'),
  ('auxivenc', 'AUXIVENC.DBF', 'Vencimientos y saldo por factura de venta'),
  ('movicobr', 'MOVICOBR.DBF', 'Recibos de cobranza'),
  ('detacobr', 'DETACOBR.DBF', 'Medios de cobro de cada recibo'),
  ('auxiapli', 'AUXIAPLI.DBF', 'Aplicacion de recibos a facturas'),
  ('movicomp', 'MOVICOMP.DBF', 'Facturas de compra y gastos'),
  ('detacomp', 'DETACOMP.DBF', 'Lineas de facturas de compra'),
  ('venccomp', 'VENCCOMP.DBF', 'Vencimientos de facturas de compra'),
  ('movipago', 'MOVIPAGO.DBF', 'Ordenes de pago'),
  ('detapago', 'DETAPAGO.DBF', 'Medios de pago de cada orden'),
  ('aplicomp', 'APLICOMP.DBF', 'Aplicacion de pagos a facturas de compra')
on conflict (tabla) do nothing;

-- 5. Control rapido de lo que llego.
create or replace view tekno.registros_resumen as
select tabla,
       count(*)                                     as total,
       count(*) filter (where not eliminado_origen) as activos,
       count(*) filter (where eliminado_origen)     as eliminados,
       max(registro_origen)                         as ultimo_id,
       max(fecha_sincronizacion)                    as ultima_sincronizacion
from tekno.registros
group by tabla
order by tabla;
