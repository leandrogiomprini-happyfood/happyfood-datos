// happyfood-sync-tablas: recibe lotes de las tablas de Tekno (todas menos ventas) desde HappyTablas.exe.
// Funcion separada de happyfood-sync a proposito: las ventas no dependen de este codigo.
// Misma autenticacion (clave secreta happyfood_sync_server) y mismas validaciones.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "npm:@supabase/server@^1";
import postgres from "npm:postgres@^3";

type Registro = {
  registro_origen: number;
  datos: Record<string, unknown>;
  eliminado_origen: boolean;
};

const dbUrl = Deno.env.get("SUPABASE_DB_URL");

const sql = dbUrl
  ? postgres(dbUrl, { prepare: false, max: 1, connect_timeout: 10, idle_timeout: 10 })
  : null;

function esObjeto(valor: unknown): valor is Record<string, unknown> {
  return typeof valor === "object" && valor !== null && !Array.isArray(valor);
}

function errorJson(mensaje: string, status = 400) {
  return Response.json({ ok: false, error: mensaje }, { status });
}

function validarRegistros(valor: unknown): Registro[] {
  if (!Array.isArray(valor) || valor.length < 1 || valor.length > 100) {
    throw new Error("Lote debe tener entre 1 y 100 registros");
  }
  const ids = new Set<number>();
  const registros: Registro[] = [];
  for (const r of valor) {
    if (
      !esObjeto(r) ||
      typeof r.registro_origen !== "number" ||
      !Number.isInteger(r.registro_origen) ||
      r.registro_origen < 1 ||
      r.registro_origen > 2147483647 ||
      !esObjeto(r.datos) ||
      typeof r.eliminado_origen !== "boolean"
    ) {
      throw new Error("Registro invalido");
    }
    if (ids.has(r.registro_origen)) throw new Error("registro_origen duplicado");
    ids.add(r.registro_origen);
    registros.push(r as Registro);
  }
  return registros;
}

export default {
  fetch: withSupabase({ auth: "secret:happyfood_sync_server" }, async (req) => {
    if (req.method !== "POST") return errorJson("Metodo no permitido", 405);

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return errorJson("JSON invalido");
    }
    if (!esObjeto(body)) return errorJson("Formato invalido");

    if (body.accion === "ping") {
      return Response.json({
        ok: true,
        servicio: "happyfood-sync-tablas",
        estado: "operativo",
        fecha_servidor: new Date().toISOString(),
      });
    }

    if (body.accion === "verificar_bd") {
      if (!sql) return errorJson("Base no configurada", 503);
      try {
        const filas = await sql`
          SELECT current_database() AS base,
                 to_regprocedure('tekno.sincronizar_registros(text,jsonb)')::text AS funcion_sql,
                 (SELECT count(*) FROM tekno.tablas_permitidas WHERE activa)::int AS tablas_activas
        `;
        return Response.json({ ok: true, accion: "verificar_bd", ...filas[0] });
      } catch (e) {
        console.error("verificar_bd:", e);
        return errorJson("Error de base de datos", 503);
      }
    }

    if (body.accion !== "sincronizar_registros") return errorJson("Accion no habilitada");

    // La lista real de tablas permitidas la valida la base (tekno.tablas_permitidas).
    if (typeof body.tabla !== "string" || !/^[a-z0-9_]{1,40}$/.test(body.tabla)) {
      return errorJson("Tabla no permitida");
    }

    let registros: Registro[];
    try {
      registros = validarRegistros(body.registros);
    } catch (e) {
      return errorJson(e instanceof Error ? e.message : "Lote invalido");
    }

    if (body.confirmar_escritura !== "ESCRIBIR_LOTE") {
      return errorJson("Lote no autorizado", 400);
    }
    if (!sql) return errorJson("Base no configurada", 503);

    try {
      const resultado = await sql`
        SELECT tekno.sincronizar_registros(${body.tabla}::text, ${sql.json(registros)}) AS respuesta
      `;
      return Response.json({
        ok: true,
        accion: "sincronizar_registros",
        tabla: body.tabla,
        recibidos: registros.length,
        resultado_sql: resultado[0].respuesta,
      });
    } catch (e) {
      console.error("sincronizar_registros:", e);
      return errorJson("No se pudo sincronizar. Revisar Logs.", 500);
    }
  }),
};
