using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

// Compara dos extracciones Tecno. No abre DBF ni realiza solicitudes de red.
// SEGURIDAD: detiene la preparacion si desaparece un registro_origen (posible PACK/reindexado).
class HappyControlIncremental
{
    const int MaxLote=100;
    class Registro
    {
        public int Id;
        public bool Eliminado;
        public Dictionary<string,string> Datos;
        public string Firma;
    }
    class Tabla
    {
        public string[] Cabecera;
        public SortedDictionary<int,Registro> Filas = new SortedDictionary<int,Registro>();
        public int Activos, Eliminados;
    }
    static int Main(string[] args)
    {
        try
        {
            if(args.Length!=3) throw new Exception("Uso: HappyControlIncremental.exe CARPETA_CSV_BASE CARPETA_CSV_NUEVA CARPETA_SALIDA_NUEVA");
            string baseDir=Path.GetFullPath(args[0]), nuevaDir=Path.GetFullPath(args[1]), salida=Path.GetFullPath(args[2]);
            if(!Directory.Exists(baseDir) || !Directory.Exists(nuevaDir)) throw new Exception("No existen ambas carpetas CSV.");
            if(String.Equals(baseDir.TrimEnd('\\'),nuevaDir.TrimEnd('\\'),StringComparison.OrdinalIgnoreCase)) throw new Exception("Carpeta base y nueva son la misma.");
            if(Directory.Exists(salida)) throw new Exception("Carpeta de salida ya existe. Elegi una NUEVA para evitar sobrescrituras: " + salida);
            if(salida.StartsWith(baseDir+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase) || salida.StartsWith(nuevaDir+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)) throw new Exception("La salida no debe estar dentro de las carpetas CSV.");
            var resultados = new List<string>();
            var lotes = new Dictionary<string,List<Dictionary<string,object>>>();
            foreach(string tabla in new[]{"ventas","ventas_detalle"})
            {
                string archivo = tabla=="ventas" ? "movivent.csv" : "DETAVENT.csv";
                Tabla anterior=Leer(Path.Combine(baseDir,archivo));
                Tabla actual=Leer(Path.Combine(nuevaDir,archivo));
                if(anterior.Cabecera.Length!=actual.Cabecera.Length) throw new Exception("CAMBIO DE COLUMNAS en " + tabla);
                for(int i=0;i<anterior.Cabecera.Length;i++) if(anterior.Cabecera[i]!=actual.Cabecera[i]) throw new Exception("CAMBIO DE COLUMNA/ORDEN en " + tabla + " posicion " + i);
                int faltantes=0, agregados=0, modificados=0, iguales=0;
                foreach(var antiguo in anterior.Filas)
                    if(!actual.Filas.ContainsKey(antiguo.Key)) faltantes++;
                if(faltantes>0) throw new Exception("DETENIDO: " + tabla + " tiene " + faltantes + " IDs que estaban en la extraccion anterior y ya no estan. Posible PACK/renumeracion de DBF. Requiere revision manual, NO se puede sincronizar por registro_origen.");
                var cambios=new List<Dictionary<string,object>>();
                foreach(var fila in actual.Filas)
                {
                    Registro viejo;
                    if(!anterior.Filas.TryGetValue(fila.Key,out viejo)) agregados++;
                    else if(viejo.Firma!=fila.Value.Firma) modificados++;
                    else { iguales++; continue; }
                    var reg=new Dictionary<string,object>();
                    reg.Add("registro_origen",fila.Key);
                    reg.Add("datos",fila.Value.Datos);
                    reg.Add("eliminado_origen",fila.Value.Eliminado);
                    cambios.Add(reg);
                }
                lotes.Add(tabla,cambios);
                resultados.Add(tabla.ToUpperInvariant()+" BASE="+anterior.Filas.Count+" ACTUAL="+actual.Filas.Count+" NUEVOS="+agregados+" MODIFICADOS="+modificados+" SIN_CAMBIOS="+iguales+" FALTANTES="+faltantes+" ACTIVOS_ACTUALES="+actual.Activos+" ELIMINADOS_ACTUALES="+actual.Eliminados+" LOTES="+((cambios.Count+MaxLote-1)/MaxLote));
                resultados.Add(tabla.ToUpperInvariant()+" SHA256_BASE="+HashArchivo(Path.Combine(baseDir,archivo))+" SHA256_NUEVO="+HashArchivo(Path.Combine(nuevaDir,archivo)));
            }
            // Ambos archivos fueron validados antes de escribir el primer archivo de salida.
            Directory.CreateDirectory(salida);
            var serializador=new JavaScriptSerializer(); serializador.MaxJsonLength=int.MaxValue;
            foreach(var elem in lotes)
            {
                for(int inicio=0, num=1;inicio<elem.Value.Count;inicio+=MaxLote,num++)
                {
                    var payload=new Dictionary<string,object>();
                    payload.Add("accion","validar_lote"); payload.Add("tabla",elem.Key);
                    payload.Add("registros",elem.Value.GetRange(inicio,Math.Min(MaxLote,elem.Value.Count-inicio)));
                    File.WriteAllText(Path.Combine(salida,elem.Key+"_cambio_"+num.ToString("0000")+".json"),serializador.Serialize(payload),new UTF8Encoding(false));
                }
            }
            string resumen="CONTROL INCREMENTAL - SIN RED / SIN ESCRITURA EN SUPABASE"+Environment.NewLine+
                "BASE="+baseDir+Environment.NewLine+"ACTUAL="+nuevaDir+Environment.NewLine+
                String.Join(Environment.NewLine,resultados.ToArray())+Environment.NewLine+
                "IMPORTANTE=Este comparador NO comprueba equivalencia de campos con Supabase ni detecta reuso de IDs tras PACK; revisar antes de enviar."+Environment.NewLine+
                "MODO=SOLO_LOCAL_NO_ENVIAR_ARCHIVOS_AUTOMATICAMENTE"+Environment.NewLine;
            File.WriteAllText(Path.Combine(salida,"RESUMEN_CAMBIOS.txt"),resumen,new UTF8Encoding(false));
            Console.WriteLine(resumen);
            Console.WriteLine("ARCHIVOS EN: "+salida);
            return 0;
        }
        catch(Exception ex) { Console.WriteLine("DETENIDO: "+ex.Message); return 1; }
    }
    static Tabla Leer(string ruta)
    {
        if(!File.Exists(ruta))throw new Exception("Falta archivo "+ruta);
        Tabla t=new Tabla();
        using(var lector=new StreamReader(ruta,Encoding.UTF8,true))
        {
            var c=LeerFila(lector);
            if(c==null||c.Count<3||c[0].TrimStart('\uFEFF')!="registro_origen"||c[1]!="eliminado_origen")throw new Exception("Cabecera invalida: "+ruta);
            c[0]=c[0].TrimStart('\uFEFF');
            var cols=new HashSet<string>(StringComparer.Ordinal);
            foreach(var col in c)if(!cols.Add(col))throw new Exception("Columna repetida "+col);
            t.Cabecera=c.ToArray();
            List<string> fila; int numero=1;
            while((fila=LeerFila(lector))!=null)
            {
                numero++;
                if(fila.Count!=c.Count)throw new Exception("Columnas diferentes en "+ruta+" fila "+numero);
                int id; bool eliminado;
                if(!int.TryParse(fila[0].Trim(),NumberStyles.None,CultureInfo.InvariantCulture,out id)||id<1||!bool.TryParse(fila[1].Trim(),out eliminado))throw new Exception("ID/estado invalido en "+ruta+" fila "+numero);
                var datos=new Dictionary<string,string>(StringComparer.Ordinal);
                for(int i=2;i<c.Count;i++)datos.Add(c[i],fila[i]);
                // Firma canonica basada en valores ordenados por columna, sin ambiguedad en separadores.
                StringBuilder sb=new StringBuilder(); sb.Append(eliminado?'1':'0');
                for(int i=2;i<fila.Count;i++){string v=fila[i];sb.Append('|').Append(v.Length).Append(':').Append(v);}
                var registro=new Registro{Id=id,Eliminado=eliminado,Datos=datos,Firma=sb.ToString()};
                if(t.Filas.ContainsKey(id))throw new Exception("ID duplicado en "+ruta+": "+id);
                t.Filas.Add(id,registro);
                if(eliminado)t.Eliminados++;else t.Activos++;
            }
        }
        if(t.Filas.Count==0)throw new Exception("CSV sin filas "+ruta);
        return t;
    }
    static string HashArchivo(string ruta)
    {
        using(var sha=SHA256.Create())using(var f=File.OpenRead(ruta))return BitConverter.ToString(sha.ComputeHash(f)).Replace("-","").ToLowerInvariant();
    }
    static List<string> LeerFila(TextReader r)
    {
        var campos=new List<string>();var actual=new StringBuilder();
        bool comillas=false,inicio=true,cerrado=false;
        while(true)
        {
            int val=r.Read();
            if(val<0){if(comillas)throw new Exception("CSV truncado dentro de comillas");if(inicio)return null;campos.Add(actual.ToString());return campos;}
            char ch=(char)val;inicio=false;
            if(comillas)
            {
                if(ch=='"'){if(r.Peek()=='"'){r.Read();actual.Append('"');}else{comillas=false;cerrado=true;}}
                else actual.Append(ch);
            }
            else if(ch==','){campos.Add(actual.ToString());actual.Length=0;cerrado=false;}
            else if(ch=='\r'||ch=='\n'){if(ch=='\r'&&r.Peek()=='\n')r.Read();campos.Add(actual.ToString());return campos;}
            else if(ch=='"'&&actual.Length==0&&!cerrado)comillas=true;
            else if(cerrado)throw new Exception("Caracter inesperado despues de comillas");
            else actual.Append(ch);
        }
    }
}
