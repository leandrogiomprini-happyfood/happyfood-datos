using System;
using System.IO;
using System.Net;
using System.Text;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;

// Cliente de lotes para Windows Server 2008 R2 / .NET Framework 4.8.
// Por seguridad NO incluye envios automaticos ni reintentos.
class HappyEnviarLote
{
    const string Url = "https://igcewbadhejtesbogewm.supabase.co/functions/v1/happyfood-sync";
    static readonly string Directorio = @"C:\HAPPY_EXTRACTOR\SYNC\LOTES_20261020";
    static readonly string ArchivoClave = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HappyFoodSync", "credencial.dpapi");
    static readonly byte[] Contexto = Encoding.UTF8.GetBytes("HappyFoodSync-Servidor-v1");

    static int Main(string[] args)
    {
        try
        {
            if (args.Length != 2 || (args[0] != "revisar" && args[0] != "enviar"))
            {
                Console.WriteLine("Uso: HappyEnviarLote.exe revisar ventas_0061.json");
                Console.WriteLine("     HappyEnviarLote.exe enviar ventas_0061.json");
                return 2;
            }
            string nombre = args[1];
            if (!System.Text.RegularExpressions.Regex.IsMatch(nombre, "^(ventas|ventas_detalle)_[0-9]{4}\\.json$", System.Text.RegularExpressions.RegexOptions.CultureInvariant))
                throw new Exception("Nombre de archivo no permitido.");
            string ruta = Path.Combine(Directorio, nombre);
            if (!File.Exists(ruta)) throw new Exception("No existe el archivo: " + ruta);
            if (!File.Exists(Path.Combine(Directorio, "RESUMEN.txt"))) throw new Exception("No existe RESUMEN.txt en la carpeta de lotes.");
            string contenido = File.ReadAllText(ruta, Encoding.UTF8);
            JavaScriptSerializer js = new JavaScriptSerializer();
            js.MaxJsonLength = Int32.MaxValue;
            Dictionary<string, object> documento = js.Deserialize<Dictionary<string, object>>(contenido);
            if (documento == null || !documento.ContainsKey("accion") || Convert.ToString(documento["accion"]) != "validar_lote")
                throw new Exception("El archivo no es un lote en modo de validacion.");
            string tabla = Convert.ToString(documento["tabla"]);
            if (tabla != "ventas" && tabla != "ventas_detalle") throw new Exception("Tabla invalida.");
            if (!nombre.StartsWith(tabla + "_", StringComparison.Ordinal)) throw new Exception("Tabla y nombre de archivo no coinciden.");
            IList registros = documento["registros"] as IList;
            if (registros == null || registros.Count < 1 || registros.Count > 100) throw new Exception("Cantidad de registros fuera de 1 a 100.");
            HashSet<int> ids = new HashSet<int>();
            int eliminados = 0, menor = Int32.MaxValue, mayor = 0;
            foreach (object item in registros)
            {
                Dictionary<string, object> fila = item as Dictionary<string, object>;
                if (fila == null || !fila.ContainsKey("registro_origen") || !fila.ContainsKey("datos") || !fila.ContainsKey("eliminado_origen"))
                    throw new Exception("Fila con estructura incompleta.");
                int id = Convert.ToInt32(fila["registro_origen"], CultureInfo.InvariantCulture);
                if (id < 1 || !ids.Add(id) || !(fila["datos"] is Dictionary<string, object>) || !(fila["eliminado_origen"] is bool))
                    throw new Exception("Registro invalido o repetido en el lote: " + id);
                menor = Math.Min(menor, id); mayor = Math.Max(mayor, id);
                if ((bool)fila["eliminado_origen"]) eliminados++;
            }
            string huella;
            using (SHA256 hash = SHA256.Create())
                huella = BitConverter.ToString(hash.ComputeHash(File.ReadAllBytes(ruta))).Replace("-", "").ToLowerInvariant();
            Console.WriteLine("HAPPY FOOD - UN SOLO LOTE, CONTROL SUPERVISADO");
            Console.WriteLine("Archivo: " + nombre);
            Console.WriteLine("Tabla: " + tabla + " | Registros: " + registros.Count + " | Eliminados: " + eliminados);
            Console.WriteLine("IDs minimo/maximo: " + menor + " / " + mayor);
            Console.WriteLine("SHA256 lote: " + huella);
            if (args[0] == "revisar")
            {
                Console.WriteLine("REVISION LOCAL CORRECTA. SIN CONEXION NI ESCRITURAS.");
                return 0;
            }
            // Esta es una operacion real, no una simulacion.
            Console.WriteLine("ATENCION: Esto escribira registros en Supabase, incluso si son anteriores a cambios mas recientes.");
            Console.WriteLine("No utilizar si el lote no fue respaldado y aprobado previamente.");
            Console.Write("Para escribir ESTE lote ingresá ESCRIBIR_LOTE: ");
            if (Console.ReadLine() != "ESCRIBIR_LOTE")
            {
                Console.WriteLine("CANCELADO. No se envio nada."); return 2;
            }
            if (!File.Exists(ArchivoClave)) throw new Exception("No se encontro credencial DPAPI para este usuario Windows.");
            string clave = Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(ArchivoClave), Contexto, DataProtectionScope.CurrentUser));
            if (!clave.StartsWith("sb_secret_", StringComparison.Ordinal)) throw new Exception("Credencial no valida.");
            documento["accion"] = "sincronizar_lote";
            documento["confirmar_escritura"] = "ESCRIBIR_LOTE";
            string salida = js.Serialize(documento);
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(Url);
            req.Method = "POST";
            req.ContentType = "application/json; charset=utf-8";
            req.Headers.Add("apikey", clave);
            req.Timeout = 90000;
            byte[] bytes = Encoding.UTF8.GetBytes(salida);
            req.ContentLength = bytes.Length;
            string respuesta;
            try
            {
                using (Stream s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);
                using (HttpWebResponse r = (HttpWebResponse)req.GetResponse())
                using (StreamReader reader = new StreamReader(r.GetResponseStream()))
                {
                    respuesta = reader.ReadToEnd();
                    Console.WriteLine("HTTP: " + (int)r.StatusCode);
                    if (r.StatusCode != HttpStatusCode.OK) throw new Exception("Estado HTTP inesperado.");
                }
            }
            catch (WebException ex)
            {
                if (ex.Response != null)
                    using (StreamReader reader = new StreamReader(ex.Response.GetResponseStream()))
                        Console.WriteLine("Respuesta HTTP de error: " + reader.ReadToEnd());
                throw new Exception("Envio NO confirmado. No reintentar sin verificar Supabase. " + ex.Message);
            }
            Dictionary<string, object> rj = js.Deserialize<Dictionary<string, object>>(respuesta);
            Dictionary<string, object> rr = rj != null && rj.ContainsKey("resultado_sql") ? rj["resultado_sql"] as Dictionary<string, object> : null;
            if (rj == null || !rj.ContainsKey("ok") || !object.Equals(rj["ok"], true) ||
                Convert.ToString(rj["accion"]) != "sincronizar_lote" || Convert.ToString(rj["tabla"]) != tabla ||
                Convert.ToInt32(rj["recibidos"]) != registros.Count || rr == null ||
                !object.Equals(rr["ok"], true) || Convert.ToInt32(rr["procesados"]) != registros.Count)
                throw new Exception("Respuesta ambigua. Verificar Supabase antes de repetir. Respuesta: " + respuesta);
            Console.WriteLine("LOTE CONFIRMADO por API y PostgreSQL: " + registros.Count + " registros.");
            Console.WriteLine("IMPORTANTE: comprobar cantidades y estado en SQL antes del siguiente lote.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine("ERROR: " + ex.Message);
            return 1;
        }
    }
}
