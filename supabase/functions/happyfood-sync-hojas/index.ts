// happyfood-sync-hojas: lee una pestaña de Google Sheets (o de un .xlsx en Drive) con la cuenta de
// servicio de Google y guarda la foto en hojas.filas (migracion 012).
// La llama pg_cron (hojas.disparar) una vez por pestaña, con la clave secreta happyfood_cron.
// Solo lectura en Google: la cuenta de servicio tiene permiso de "Lector" en las planillas.
//
// Secretos de la funcion (Edge Functions > Secrets):
//   GOOGLE_SA_JSON   contenido completo del archivo .json de la cuenta de servicio
//   SUPABASE_DB_URL  lo provee Supabase
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "npm:@supabase/server@^1";
import postgres from "npm:postgres@^3";
import * as XLSX from "npm:xlsx@0.18.5";

type Fuente = { fuente: string; planilla_id: string; hoja: string; tipo: "sheet" | "xlsx" };
type Celda = string | number | boolean | null;

const dbUrl = Deno.env.get("SUPABASE_DB_URL");
const sql = dbUrl
  ? postgres(dbUrl, { prepare: false, max: 1, connect_timeout: 10, idle_timeout: 10 })
  : null;

const ALCANCES = [
  "https://www.googleapis.com/auth/spreadsheets.readonly",
  "https://www.googleapis.com/auth/drive.readonly",
].join(" ");

function errorJson(mensaje: string, status = 400) {
  return Response.json({ ok: false, error: mensaje }, { status });
}

// ---------- autenticacion con Google (JWT firmado con la clave de la cuenta de servicio)
function base64url(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const texto = (s: string) => base64url(new TextEncoder().encode(s));

let tokenCache: { token: string; vence: number } | null = null;

async function tokenGoogle(): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);
  if (tokenCache && tokenCache.vence > ahora + 120) return tokenCache.token;

  const crudo = Deno.env.get("GOOGLE_SA_JSON");
  if (!crudo) throw new Error("Falta el secreto GOOGLE_SA_JSON");
  const cuenta = JSON.parse(crudo) as { client_email: string; private_key: string };

  const sinFirmar = texto(JSON.stringify({ alg: "RS256", typ: "JWT" })) + "." + texto(JSON.stringify({
    iss: cuenta.client_email,
    scope: ALCANCES,
    aud: "https://oauth2.googleapis.com/token",
    iat: ahora,
    exp: ahora + 3600,
  }));
  const pem = cuenta.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const clave = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const firma = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", clave, new TextEncoder().encode(sinFirmar)),
  );

  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: sinFirmar + "." + base64url(firma),
    }),
  });
  const j = await r.json();
  if (!r.ok || !j.access_token) throw new Error("Google rechazo la cuenta de servicio: " + (j.error_description || j.error || r.status));
  tokenCache = { token: j.access_token, vence: ahora + (j.expires_in || 3600) };
  return tokenCache.token;
}

// ---------- lectura
function limpiar(filas: Celda[][]): Celda[][] {
  const out = filas.map((f) => (f || []).map((v) => (v === "" || v === undefined ? null : v)));
  // quitar filas vacias del final y columnas vacias del final de cada fila
  for (const f of out) while (f.length && f[f.length - 1] === null) f.pop();
  while (out.length && out[out.length - 1].length === 0) out.pop();
  return out;
}

async function pestanasDisponibles(id: string, token: string): Promise<string> {
  try {
    const r = await fetch(
      `https://sheets.googleapis.com/v4/spreadsheets/${id}?fields=sheets.properties.title`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (!r.ok) return "";
    const j = await r.json();
    return (j.sheets || []).map((s: { properties: { title: string } }) => s.properties.title).join(" | ");
  } catch {
    return "";
  }
}

async function leerSheet(f: Fuente, token: string): Promise<Celda[][]> {
  const rango = encodeURIComponent("'" + f.hoja.replace(/'/g, "''") + "'");
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${f.planilla_id}/values/${rango}` +
    `?valueRenderOption=UNFORMATTED_VALUE&dateTimeRenderOption=FORMATTED_STRING&majorDimension=ROWS`;
  const r = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (r.status === 403 || r.status === 404) {
    throw new Error(`Sin acceso a la planilla (${r.status}). Compartirla con el email de la cuenta de servicio como Lector.`);
  }
  if (r.status === 400) {
    const disp = await pestanasDisponibles(f.planilla_id, token);
    throw new Error(`No existe la pestaña "${f.hoja}". Pestañas: ${disp || "(no se pudieron listar)"}`);
  }
  if (!r.ok) throw new Error(`Google respondio ${r.status}`);
  const j = await r.json();
  return limpiar((j.values || []) as Celda[][]);
}

async function leerXlsx(f: Fuente, token: string): Promise<Celda[][]> {
  const r = await fetch(
    `https://www.googleapis.com/drive/v3/files/${f.planilla_id}?alt=media&supportsAllDrives=true`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (r.status === 403 || r.status === 404) {
    throw new Error(`Sin acceso al archivo (${r.status}). Compartirlo con el email de la cuenta de servicio como Lector.`);
  }
  if (!r.ok) throw new Error(`Google Drive respondio ${r.status}`);
  const libro = XLSX.read(new Uint8Array(await r.arrayBuffer()), { type: "array", sheets: [f.hoja] });
  const hoja = libro.Sheets[f.hoja];
  if (!hoja) throw new Error(`No existe la pestaña "${f.hoja}". Pestañas: ${libro.SheetNames.join(" | ")}`);
  // Leer desde A1 para que la fila 1 de la planilla sea la fila 1 guardada (igual que en Sheets).
  const rango = XLSX.utils.decode_range(hoja["!ref"] || "A1");
  rango.s = { r: 0, c: 0 };
  const filas = XLSX.utils.sheet_to_json(hoja, {
    header: 1, raw: true, defval: null, blankrows: true, range: rango,
  }) as Celda[][];
  return limpiar(filas);
}

async function hash(valor: unknown): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(valor)));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ---------- servidor
export default {
  fetch: withSupabase({ auth: "secret:happyfood_cron" }, async (req) => {
    if (req.method !== "POST") return errorJson("Metodo no permitido", 405);
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return errorJson("JSON invalido");
    }

    if (body.accion === "ping") {
      return Response.json({ ok: true, servicio: "happyfood-sync-hojas", fecha_servidor: new Date().toISOString() });
    }
    if (body.accion !== "leer") return errorJson("Accion no habilitada");
    if (typeof body.fuente !== "string" || !/^[a-z0-9_]{1,40}$/.test(body.fuente)) return errorJson("Fuente invalida");
    if (!sql) return errorJson("Base no configurada", 503);

    const filasFuente = await sql<Fuente[]>`
      select fuente, planilla_id, hoja, tipo from hojas.fuentes where fuente = ${body.fuente} and activa`;
    if (!filasFuente.length) return errorJson("Fuente no habilitada");
    const f = filasFuente[0];

    try {
      const token = await tokenGoogle();
      const filas = f.tipo === "xlsx" ? await leerXlsx(f, token) : await leerSheet(f, token);
      const h = await hash(filas);
      const res = await sql`select hojas.cargar(${f.fuente}, ${h}, ${sql.json(filas)}) as r`;
      return Response.json(res[0].r);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`leer ${f.fuente}:`, msg);
      try {
        await sql`select hojas.registrar_error(${f.fuente}, ${msg})`;
      } catch (e2) {
        console.error("registrar_error:", e2);
      }
      return errorJson(msg, 502);
    }
  }),
};
