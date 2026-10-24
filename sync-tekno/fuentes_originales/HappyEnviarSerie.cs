using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Globalization;

// Control secuencial; usa HappyEnviarLote.exe previamente validado.
// No hay reintentos automaticos. Una escritura incierta bloquea siguientes ejecuciones.
class HappyEnviarSerie
{
    const string Raiz = @"C:\HAPPY_EXTRACTOR\SYNC";
    static readonly string Lotes = Path.Combine(Raiz, "LOTES_20261020");
    static readonly string Estado = Path.Combine(Raiz, "CONTROL_ENVIOS_20261020");
    static readonly string Bitacora = Path.Combine(Estado, "estado.txt");
    static readonly string Cliente = Path.Combine(Raiz, "HappyEnviarLote.exe");

    static int Main(string[] args)
    {
        try
        {
            if (args.Length != 1) throw new Exception("Uso: HappyEnviarSerie.exe ventas_prueba | ventas_resto | detalle_prueba | detalle_resto");
            string tabla, clave;
            int inicio, fin;
            switch (args[0])
            {
                case "ventas_prueba": tabla = "ventas"; inicio = 1; fin = 5; clave = "AUTORIZO_5_VENTAS"; break;
                case "ventas_resto": tabla = "ventas"; inicio = 6; fin = 60; clave = "AUTORIZO_55_VENTAS"; break;
                case "detalle_prueba": tabla = "ventas_detalle"; inicio = 1; fin = 1; clave = "AUTORIZO_1_DETALLE"; break;
                case "detalle_resto": tabla = "ventas_detalle"; inicio = 2; fin = 400; clave = "AUTORIZO_399_DETALLES"; break;
                default: throw new Exception("Fase no permitida: " + args[0]);
            }
            if (!File.Exists(Cliente)) throw new Exception("No existe HappyEnviarLote.exe; compilar primero 01_COMPILAR_ENVIO.bat");
            if (!File.Exists(Path.Combine(Lotes,"RESUMEN.txt"))) throw new Exception("No existe RESUMEN.txt");
            Directory.CreateDirectory(Estado);
            string resumen = File.ReadAllText(Path.Combine(Lotes,"RESUMEN.txt"), Encoding.UTF8);
            if (!resumen.Contains("VENTAS TOTAL=6053 ACTIVOS=5922 ELIMINADOS=131 LOTES=61") ||
                !resumen.Contains("VENTAS_DETALLE TOTAL=39929 ACTIVOS=29453 ELIMINADOS=10476 LOTES=400"))
                throw new Exception("RESUMEN.txt no coincide con la extraccion validada; DETENIDO.");
            // Congelar la entrada antes de realizar cualquier envio.
            var nombres = new List<string>();
            var huellas = new Dictionary<string,string>(StringComparer.Ordinal);
            for (int n=inicio; n<=fin; n++)
            {
                string nombre = tabla + "_" + n.ToString("0000",CultureInfo.InvariantCulture) + ".json";
                string ruta = Path.Combine(Lotes,nombre);
                if (!File.Exists(ruta)) throw new Exception("Falta lote " + nombre);
                nombres.Add(nombre);
                huellas[nombre] = Hash(ruta);
            }
            var ok = new Dictionary<string,string>(StringComparer.Ordinal);
            var pendientes = new Dictionary<string,string>(StringComparer.Ordinal);
            if (File.Exists(Bitacora))
            {
                foreach (string linea in File.ReadAllLines(Bitacora, Encoding.UTF8))
                {
                    string[] p=linea.Split('|');
                    if(p.Length!=3) throw new Exception("Bitacora ilegible. No modificarla manualmente.");
                    if(p[0]=="START") pendientes[p[1]]=p[2];
                    else if(p[0]=="OK") { if(!pendientes.ContainsKey(p[1]) || pendientes[p[1]]!=p[2]) throw new Exception("Bitacora inconsistente para " + p[1]); ok[p[1]]=p[2]; pendientes.Remove(p[1]); }
                    else throw new Exception("Entrada desconocida en bitacora");
                }
            }
            if(pendientes.Count>0)
            {
                foreach(var x in pendientes) Console.WriteLine("LOTE DE RESULTADO INCIERTO: " + x.Key);
                throw new Exception("Existe un START sin OK. Verificar en Supabase antes de continuar. Sin reintentos automáticos.");
            }
            foreach(var x in ok)
            {
                string ruta=Path.Combine(Lotes,x.Key);
                if(!File.Exists(ruta) || Hash(ruta)!=x.Value) throw new Exception("Archivo ya enviado fue modificado: " + x.Key);
            }
            Console.WriteLine("HAPPY FOOD - ENVIO SERIADO SUPERVISADO");
            Console.WriteLine("Fase: " + args[0] + " | tabla: " + tabla + " | lotes: " + nombres.Count);
            Console.WriteLine("Lote ventas_0061.json ya fue enviado y verificado manualmente: NO SE REENVIA.");
            Console.WriteLine("Se usaran lotes de la extraccion 20/10/2026; NO son datos actuales de Tecno.");
            Console.WriteLine("Puede sobrescribir datos mas recientes que la extraccion.");
            Console.WriteLine("Bitacora persistente: " + Bitacora);
            Console.Write("Escribi " + clave + " para iniciar esta fase: ");
            if(Console.ReadLine()!=clave) {Console.WriteLine("CANCELADO");return 2;}
            int enviados=0, omitidos=0;
            foreach(string nombre in nombres)
            {
                if(ok.ContainsKey(nombre)) { Console.WriteLine("YA CONFIRMADO: " + nombre); omitidos++; continue; }
                if(Hash(Path.Combine(Lotes,nombre))!=huellas[nombre]) throw new Exception("Lote modificado antes de enviar: " + nombre);
                Anotar("START|" + nombre + "|" + huellas[nombre]);
                Console.WriteLine("ENVIANDO: " + nombre);
                // El programa existente revisa JSON, firma, la respuesta HTTP y el resultado de SQL.
                // El input se suministra exclusivamente al proceso hijo, despues de la confirmacion de fase.
                ProcessStartInfo psi=new ProcessStartInfo(Cliente,"enviar " + nombre);
                psi.UseShellExecute=false;
                psi.RedirectStandardInput=true;
                psi.RedirectStandardOutput=true;
                psi.RedirectStandardError=true;
                psi.CreateNoWindow=true;
                using(Process p=Process.Start(psi))
                {
                    p.StandardInput.WriteLine("ESCRIBIR_LOTE");
                    p.StandardInput.Close();
                    string salida=p.StandardOutput.ReadToEnd();
                    string error=p.StandardError.ReadToEnd();
                    p.WaitForExit();
                    Console.WriteLine(salida);
                    if(error.Length>0) Console.WriteLine(error);
                    if(p.ExitCode!=0 || !salida.Contains("LOTE CONFIRMADO por API y PostgreSQL:"))
                        throw new Exception("ENVIO NO CONFIRMADO: " + nombre + ". Revisar Supabase; START queda pendiente intencionalmente.");
                }
                Anotar("OK|" + nombre + "|" + huellas[nombre]);
                enviados++;
                Console.WriteLine("CONFIRMADO: " + nombre + " | completados nuevos=" + enviados);
            }
            Console.WriteLine("FASE TERMINADA: " + args[0] + " | enviados=" + enviados + " | ya_confirmados=" + omitidos);
            Console.WriteLine("NO avanzar a la siguiente fase sin verificar los recuentos en Supabase.");
            return 0;
        }
        catch(Exception e) { Console.WriteLine("DETENIDO: " + e.Message); return 1; }
    }
    static string Hash(string ruta)
    {
        using(var sha=SHA256.Create()) using(var f=File.OpenRead(ruta))
            return BitConverter.ToString(sha.ComputeHash(f)).Replace("-","").ToLowerInvariant();
    }
    static void Anotar(string linea)
    {
        using(var fs=new FileStream(Bitacora,FileMode.Append,FileAccess.Write,FileShare.Read))
        {
            byte[] b=new UTF8Encoding(false).GetBytes(linea+Environment.NewLine);
            fs.Write(b,0,b.Length); fs.Flush(true);
        }
    }
}
