-- Copia de referencia de la función en producción (obtenida con pg_get_functiondef el 24/10/2026).
-- NO es una migración: ya existe en Supabase. Sirve para versionar y comparar cambios.
CREATE OR REPLACE FUNCTION tekno.sincronizar_lote(p_tabla text, p_registros jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_registro JSONB;
    v_id INTEGER;
    v_datos JSONB;
    v_eliminado BOOLEAN;
    v_procesados INTEGER := 0;
    v_ids INTEGER[] := ARRAY[]::INTEGER[];
BEGIN
    IF p_tabla NOT IN ('ventas', 'ventas_detalle')
       OR p_tabla IS NULL THEN
        RAISE EXCEPTION 'Tabla no permitida';
    END IF;

    IF p_registros IS NULL
       OR jsonb_typeof(p_registros) <> 'array'
       OR jsonb_array_length(p_registros) NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'Lote invalido';
    END IF;

    -- Validar todo el lote antes de escribir.
    FOR v_registro IN
        SELECT value
        FROM jsonb_array_elements(p_registros)
    LOOP
        IF jsonb_typeof(v_registro) <> 'object'
           OR jsonb_typeof(v_registro->'registro_origen') <> 'number'
           OR (v_registro->>'registro_origen') !~ '^[0-9]+$'
           OR jsonb_typeof(v_registro->'datos') <> 'object'
           OR jsonb_typeof(v_registro->'eliminado_origen') <> 'boolean'
        THEN
            RAISE EXCEPTION 'Registro invalido';
        END IF;

        v_id := (v_registro->>'registro_origen')::INTEGER;

        IF v_id < 1 OR v_id = ANY(v_ids) THEN
            RAISE EXCEPTION 'Identificador invalido o duplicado';
        END IF;

        v_ids := array_append(v_ids, v_id);
    END LOOP;

    -- Insertar o actualizar registros.
    FOR v_registro IN
        SELECT value
        FROM jsonb_array_elements(p_registros)
    LOOP
        v_id := (v_registro->>'registro_origen')::INTEGER;
        v_datos := v_registro->'datos';
        v_eliminado :=
            (v_registro->>'eliminado_origen')::BOOLEAN;

        IF p_tabla = 'ventas' THEN

            INSERT INTO tekno.ventas (
                registro_origen,
                datos,
                eliminado_origen
            )
            VALUES (
                v_id,
                v_datos,
                v_eliminado
            )
            ON CONFLICT (registro_origen)
            DO UPDATE SET
                datos = EXCLUDED.datos,
                eliminado_origen = EXCLUDED.eliminado_origen,
                fecha_sincronizacion = now()
            WHERE
                tekno.ventas.datos
                    IS DISTINCT FROM EXCLUDED.datos
                OR tekno.ventas.eliminado_origen
                    IS DISTINCT FROM EXCLUDED.eliminado_origen;

        ELSE

            INSERT INTO tekno.ventas_detalle (
                registro_origen,
                datos,
                eliminado_origen
            )
            VALUES (
                v_id,
                v_datos,
                v_eliminado
            )
            ON CONFLICT (registro_origen)
            DO UPDATE SET
                datos = EXCLUDED.datos,
                eliminado_origen = EXCLUDED.eliminado_origen,
                fecha_sincronizacion = now()
            WHERE
                tekno.ventas_detalle.datos
                    IS DISTINCT FROM EXCLUDED.datos
                OR tekno.ventas_detalle.eliminado_origen
                    IS DISTINCT FROM EXCLUDED.eliminado_origen;

        END IF;

        v_procesados := v_procesados + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'ok', true,
        'tabla', p_tabla,
        'procesados', v_procesados
    );
END;
$function$;
