using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Net;
using System.Security.Cryptography;
using System.Threading;
using System.Web.Script.Serialization;

// Happy Food - Sincronizador de tablas de Tekno (todas menos ventas) -> Supabase tekno.registros.
// Windows Server 2008 R2, .NET Framework 4.x. Nunca modifica Tekno (lee una instantanea VSS).
// Convive con HappyAuto.exe (ventas): comparten el mismo candado, nunca corren a la vez.
//
// Diferencias con HappyAuto:
//  - La lista de tablas sale de tablas_tekno.txt (una linea por tabla), no del codigo.
//  - La carga en Supabase es idempotente (upsert por tabla + registro_origen): si un lote
//    falla por red, la tabla no avanza su base y se reenvia en la proxima corrida.
//  - Solo se bloquea (REQUIERE_REVISION.txt) ante sospecha de PACK o renumeracion del DBF.
class HappyTablas {
 const string Root=@"C:\HAPPY_EXTRACTOR";
 const string Sync=Root+@"\SYNC";
 const string State=Sync+@"\AUTO_TABLAS";
 const string BaseDir=State+@"\BASE";
 const string SharedLock=Sync+@"\AUTO_ESTADO\en_ejecucion.lock";   // el mismo que usa HappyAuto
 const string Block=State+@"\REQUIERE_REVISION.txt";
 const string Enabled=State+@"\AUTORIZACION_AUTOMATICA.txt";
 const string Token="AUTORIZO_SYNC_TABLAS_TEKNO";
 const string ConfigFile=Sync+@"\tablas_tekno.txt";
 const string PingFile=State+@"\healthcheck_url.txt";
 const string Endpoint="https://igcewbadhejtesbogewm.supabase.co/functions/v1/happyfood-sync";
 const string Extractor=Root+@"\happy_extractor_v1\Extractor.exe";
 const string Original=@"X:\TEKNO\ssoft.hap\DATOS\";
 const int MaxLote=100;
 static string LogFile;
 static bool Scheduled=false;
 static readonly JavaScriptSerializer J=new JavaScriptSerializer { MaxJsonLength=int.MaxValue, RecursionLimit=100 };

 class TablaConfig { public string Tabla; public string Archivo; public string[] Claves; }
 class Registro { public int Id; public bool Eliminado; public Dictionary<string,string> Datos; public string Firma; }
 class Csv { public string[] Cabecera; public SortedDictionary<int,Registro> Filas=new SortedDictionary<int,Registro>(); }

 static int Main(string[] args) {
  try {
   Directory.CreateDirectory(State); Directory.CreateDirectory(BaseDir);
   if(args.Length!=1) throw new Exception("Uso: HappyTablas.exe probar | sincronizar | estado");
   var tablas=LeerConfig();
   if(args[0]=="estado") { Estado(tablas); return 0; }
   if(args[0]!="probar" && args[0]!="sincronizar") throw new Exception("Modo invalido.");
   bool write=args[0]=="sincronizar";
   Scheduled=write;
   if(File.Exists(Block)) throw new Exception("DETENIDO: existe REQUIERE_REVISION.txt en AUTO_TABLAS. Revisar antes de seguir.");
   if(write && (!File.Exists(Enabled) || File.ReadAllText(Enabled).Trim()!=Token)) throw new Exception("Escritura automatica NO autorizada. Falta "+Enabled);
   using(var l=TomarCandado()) {
    if(l==null) { Console.WriteLine("OCUPADO: HappyAuto esta corriendo. Se reintenta en la proxima ejecucion."); return 2; }
    Run(write,tablas);
   }
   if(Scheduled) Ping("");
   return 0;
  } catch(Exception ex) {
   Console.WriteLine("DETENIDO: "+ex.Message);
   if(LogFile!=null) try { File.AppendAllText(LogFile,"ERROR "+DateTime.Now.ToString("s")+" "+ex.ToString()+Environment.NewLine); } catch {}
   if(Scheduled) Ping("/fail");
   return 1;
  }
 }

 // Espera hasta 5 minutos a que HappyAuto libere el candado compartido.
 static FileStream TomarCandado() {
  Directory.CreateDirectory(Path.GetDirectoryName(SharedLock));
  for(int i=0;i<20;i++) {
   try { return new FileStream(SharedLock,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None); }
   catch(IOException) { Thread.Sleep(15000); }
  }
  return null;
 }

 static List<TablaConfig> LeerConfig() {
  if(!File.Exists(ConfigFile)) throw new Exception("Falta "+ConfigFile);
  var res=new List<TablaConfig>(); var vistas=new HashSet<string>();
  int n=0;
  foreach(string linea in File.ReadAllLines(ConfigFile,Encoding.UTF8)) {
   n++; string s=linea.Trim();
   if(s.Length==0||s.StartsWith("#")) continue;
   var p=s.Split('|');
   if(p.Length!=3) throw new Exception("tablas_tekno.txt linea "+n+": formato tabla|ARCHIVO.DBF|CLAVE1,CLAVE2");
   var t=new TablaConfig { Tabla=p[0].Trim(), Archivo=p[1].Trim(), Claves=p[2].Split(',').Select(x=>x.Trim()).Where(x=>x.Length>0).ToArray() };
   if(!Regex.IsMatch(t.Tabla,"^[a-z0-9_]{1,40}$")) throw new Exception("Nombre de tabla invalido linea "+n+": "+t.Tabla);
   if(t.Tabla=="ventas"||t.Tabla=="ventas_detalle"||t.Archivo.Equals("MOVIVENT.DBF",StringComparison.OrdinalIgnoreCase)||t.Archivo.Equals("DETAVENT.DBF",StringComparison.OrdinalIgnoreCase)) throw new Exception("Las ventas van por HappyAuto, no por este programa (linea "+n+").");
   if(!Regex.IsMatch(t.Archivo,@"^[A-Za-z0-9_]{1,8}\.[Dd][Bb][Ff]$")) throw new Exception("Archivo invalido linea "+n+": "+t.Archivo);
   if(t.Claves.Length==0) throw new Exception("Faltan claves de identidad linea "+n);
   if(!vistas.Add(t.Tabla)) throw new Exception("Tabla repetida: "+t.Tabla);
   res.Add(t);
  }
  if(res.Count==0) throw new Exception("tablas_tekno.txt no tiene tablas activas.");
  return res;
 }

 static void Estado(List<TablaConfig> tablas) {
  Console.WriteLine("BLOQUEADO: "+File.Exists(Block)+" / AUTORIZADO: "+(File.Exists(Enabled)&&File.ReadAllText(Enabled).Trim()==Token)+" / AVISO: "+File.Exists(PingFile));
  foreach(var t in tablas) {
   string b=Path.Combine(BaseDir,t.Tabla+".csv");
   Console.WriteLine(t.Tabla.PadRight(10)+" "+(File.Exists(b)?"base del "+File.GetLastWriteTime(b).ToString("yyyy-MM-dd HH:mm"):"SIN BASE (la proxima corrida hace la carga inicial)"));
  }
 }

 static void Run(bool write,List<TablaConfig> tablas) {
  if(!File.Exists(Extractor)) throw new Exception("Falta "+Extractor);
  string stamp=DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
  string run=Path.Combine(State,"EJECUCIONES",stamp);
  Directory.CreateDirectory(run); LogFile=Path.Combine(run,"ejecucion.log");
  string dbfs=Path.Combine(run,"DBF"), csv=Path.Combine(run,"CSV");
  Directory.CreateDirectory(dbfs); Directory.CreateDirectory(csv);
  Log("INICIO modo="+(write?"SINCRONIZAR":"SOLO_PRUEBA")+" tablas="+tablas.Count+" run="+run);

  CopiarDesdeVss(tablas,dbfs);
  RunProcess(Extractor,"\""+dbfs+"\" \""+csv+"\"",600000);

  // 1. Comparar todo antes de enviar nada.
  var pendientes=new List<KeyValuePair<TablaConfig,List<Dictionary<string,object>>>>();
  var resumen=new StringBuilder();
  foreach(var t in tablas) {
   string nuevo=Path.Combine(csv,Path.GetFileNameWithoutExtension(t.Archivo)+".csv");
   if(!File.Exists(nuevo)) throw new Exception("El extractor no genero "+nuevo);
   Csv actual=Leer(nuevo);
   foreach(string k in t.Claves) if(Array.IndexOf(actual.Cabecera,k)<0) throw new Exception(t.Tabla+": la clave "+k+" no existe en el DBF");
   string basePath=Path.Combine(BaseDir,t.Tabla+".csv");
   var cambios=new List<Dictionary<string,object>>();
   int nuevos=0, modificados=0, iguales=0;
   if(File.Exists(basePath)) {
    Csv anterior=Leer(basePath);
    if(!anterior.Cabecera.SequenceEqual(actual.Cabecera)) Bloquear(t.Tabla+": cambiaron las columnas del DBF.");
    int faltantes=anterior.Filas.Keys.Count(id=>!actual.Filas.ContainsKey(id));
    if(faltantes>0) Bloquear(t.Tabla+": "+faltantes+" registros de la base anterior ya no estan. Posible PACK o renumeracion.");
    foreach(var f in actual.Filas) {
     Registro viejo;
     if(!anterior.Filas.TryGetValue(f.Key,out viejo)) nuevos++;
     else if(viejo.Firma==f.Value.Firma) { iguales++; continue; }
     else {
      foreach(string k in t.Claves) if(viejo.Datos[k].Trim()!=f.Value.Datos[k].Trim()) Bloquear(t.Tabla+": cambio el campo de identidad "+k+" en registro "+f.Key+". Posible PACK o reasignacion.");
      modificados++;
     }
     cambios.Add(Payload(f.Value));
    }
   } else {
    foreach(var f in actual.Filas) { nuevos++; cambios.Add(Payload(f.Value)); }
   }
   string linea=t.Tabla.ToUpperInvariant()+" ACTUAL="+actual.Filas.Count+" NUEVOS="+nuevos+" MODIFICADOS="+modificados+" SIN_CAMBIOS="+iguales+(File.Exists(basePath)?"":" (CARGA INICIAL)");
   Log(linea); resumen.AppendLine(linea);
   pendientes.Add(new KeyValuePair<TablaConfig,List<Dictionary<string,object>>>(t,cambios));
  }
  File.WriteAllText(Path.Combine(run,"RESUMEN_CAMBIOS.txt"),resumen.ToString(),new UTF8Encoding(false));
  if(!write) { Log("PRUEBA CORRECTA: SIN CONEXION NI ESCRITURA. Ver RESUMEN_CAMBIOS.txt"); return; }

  // 2. Enviar tabla por tabla. Una tabla avanza su base solo si TODOS sus lotes se confirmaron.
  int lotesTotales=0;
  foreach(var p in pendientes) {
   var t=p.Key; var cambios=p.Value;
   string nuevo=Path.Combine(csv,Path.GetFileNameWithoutExtension(t.Archivo)+".csv");
   for(int i=0;i<cambios.Count;i+=MaxLote) {
    var lote=cambios.GetRange(i,Math.Min(MaxLote,cambios.Count-i));
    Send(t.Tabla,lote);
    lotesTotales++;
   }
   if(cambios.Count>0) Log("OK "+t.Tabla+" registros="+cambios.Count);
   Promover(nuevo,Path.Combine(BaseDir,t.Tabla+".csv"));
  }
  Log("CICLO COMPLETO. lotes="+lotesTotales);
 }

 static Dictionary<string,object> Payload(Registro r) {
  var d=new Dictionary<string,object>();
  d.Add("registro_origen",r.Id); d.Add("datos",r.Datos); d.Add("eliminado_origen",r.Eliminado);
  return d;
 }

 static void Bloquear(string motivo) {
  File.WriteAllText(Block,DateTime.Now.ToString("s")+" "+motivo+Environment.NewLine+"No borrar sin revisar. Run log: "+LogFile,Encoding.UTF8);
  throw new Exception("BLOQUEADO: "+motivo);
 }

 // La base de cada tabla se reemplaza por la extraccion confirmada (copia temporal + reemplazo).
 static void Promover(string nuevo,string destino) {
  string tmp=destino+".tmp";
  File.Copy(nuevo,tmp,true);
  if(File.Exists(destino)) File.Delete(destino);
  File.Move(tmp,destino);
 }

 static void CopiarDesdeVss(List<TablaConfig> tablas,string destino) {
  Guid shadow=Guid.Empty;
  HashSet<Guid> before=ListShadows();
  if(DriveExists(@"X:\")) throw new Exception("La unidad X: esta ocupada. No se crea VSS.");
  string run=Path.GetDirectoryName(destino);
  try {
   string script=Path.Combine(run,"crear_vss.txt");
   File.WriteAllText(script,"set context persistent nowriters\r\nadd volume F: alias happyf\r\ncreate\r\nexpose %happyf% X:\r\n",Encoding.ASCII);
   RunProcess("diskshadow.exe","/s \""+script+"\"",120000);
   var after=ListShadows(); after.ExceptWith(before);
   if(after.Count!=1) throw new Exception("No se pudo identificar una unica nueva instantanea VSS. Cantidad nueva="+after.Count);
   shadow=after.First();
   Log("VSS creada, ID="+shadow.ToString("D"));
   if(!DriveExists(@"X:\")) throw new Exception("La instantanea no quedo expuesta como X:");
   foreach(var t in tablas) {
    string src=Path.Combine(Original,t.Archivo), dest=Path.Combine(destino,t.Archivo);
    if(!File.Exists(src)) throw new Exception("DBF no hallado en VSS: "+src);
    File.Copy(src,dest,false);
    if(new FileInfo(dest).Length!=new FileInfo(src).Length) throw new Exception("Tamano DBF distinto: "+t.Archivo);
   }
   Log("COPIA_OK "+tablas.Count+" DBF");
  } finally {
   if(shadow==Guid.Empty) { try { var fresh=ListShadows(); fresh.ExceptWith(before); if(fresh.Count==1) shadow=fresh.First(); } catch {} }
   if(shadow!=Guid.Empty) {
    try {
     string cleanup=Path.Combine(run,"liberar_vss.txt");
     File.WriteAllText(cleanup,"delete shadows id {"+shadow.ToString("D")+"}\r\n",Encoding.ASCII);
     RunProcess("diskshadow.exe","/s \""+cleanup+"\"",120000);
     if(ListShadows().Contains(shadow)) throw new Exception("VSS aun presente.");
     Log("VSS eliminada, ID="+shadow.ToString("D"));
    } catch(Exception ex) { File.WriteAllText(Block,"ERROR DE LIMPIEZA VSS: "+ex.Message); throw; }
   } else {
    var leftovers=ListShadows(); leftovers.ExceptWith(before);
    if(leftovers.Count>0) { File.WriteAllText(Block,"Instantaneas nuevas no identificadas: "+String.Join(",",leftovers.Select(x=>x.ToString()).ToArray())); throw new Exception("VSS sin identificar; revisar estado."); }
   }
  }
 }

 static void Send(string tabla,List<Dictionary<string,object>> registros) {
  int cnt=registros.Count;
  if(cnt<1||cnt>MaxLote) throw new Exception("Cantidad invalida");
  string keyPath=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"HappyFoodSync","credencial.dpapi");
  if(!File.Exists(keyPath)) throw new Exception("DPAPI no existe para esta cuenta Windows. Usar la misma cuenta que HappyAuto.");
  byte[] entropy=Encoding.UTF8.GetBytes("HappyFoodSync-Servidor-v1");
  string key=Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(keyPath),entropy,DataProtectionScope.CurrentUser));
  if(!key.StartsWith("sb_secret_",StringComparison.Ordinal)) throw new Exception("Credencial inesperada");
  var doc=new Dictionary<string,object>();
  doc.Add("accion","sincronizar_registros"); doc.Add("tabla",tabla); doc.Add("registros",registros); doc.Add("confirmar_escritura","ESCRIBIR_LOTE");
  byte[] bytes=Encoding.UTF8.GetBytes(J.Serialize(doc));
  ServicePointManager.SecurityProtocol=(SecurityProtocolType)3072;
  var req=(HttpWebRequest)WebRequest.Create(Endpoint);
  req.Method="POST"; req.ContentType="application/json; charset=utf-8"; req.Headers.Add("apikey",key);
  req.Timeout=90000; req.ReadWriteTimeout=90000; req.ContentLength=bytes.Length;
  using(Stream s=req.GetRequestStream()) s.Write(bytes,0,bytes.Length);
  string response;
  using(var resp=(HttpWebResponse)req.GetResponse()) {
   if(resp.StatusCode!=HttpStatusCode.OK) throw new Exception("HTTP "+(int)resp.StatusCode);
   using(var r=new StreamReader(resp.GetResponseStream())) response=r.ReadToEnd();
  }
  var reply=J.Deserialize<Dictionary<string,object>>(response);
  var sqlResp=reply.ContainsKey("resultado_sql")?reply["resultado_sql"] as Dictionary<string,object>:null;
  if(!Equals(reply["ok"],true)||Convert.ToString(reply["tabla"])!=tabla||Convert.ToInt32(reply["recibidos"])!=cnt||sqlResp==null||!Equals(sqlResp["ok"],true)||Convert.ToInt32(sqlResp["procesados"])!=cnt)
   throw new Exception("Respuesta no confirmada para "+tabla+". La tabla no avanza; se reenvia en la proxima corrida.");
 }

 // Aviso externo (Healthchecks.io). Nunca cambia el resultado de la sincronizacion.
 static void Ping(string suffix) {
  try {
   if(!File.Exists(PingFile)) return;
   string url=File.ReadAllText(PingFile).Trim();
   if(!url.StartsWith("https://")) return;
   ServicePointManager.SecurityProtocol=(SecurityProtocolType)3072;
   var req=(HttpWebRequest)WebRequest.Create(url+suffix);
   req.Method="GET"; req.Timeout=10000; req.ReadWriteTimeout=10000;
   using(var resp=(HttpWebResponse)req.GetResponse()) {}
  } catch {}
 }

 // ---- Lectura del CSV del extractor (mismo formato y reglas que HappyControlIncremental) ----
 static Csv Leer(string ruta) {
  var t=new Csv();
  using(var lector=new StreamReader(ruta,Encoding.UTF8,true)) {
   var c=LeerFila(lector);
   if(c==null||c.Count<3||c[0].TrimStart('\uFEFF')!="registro_origen"||c[1]!="eliminado_origen") throw new Exception("Cabecera invalida: "+ruta);
   c[0]=c[0].TrimStart('\uFEFF');
   var cols=new HashSet<string>(StringComparer.Ordinal);
   foreach(var col in c) if(!cols.Add(col)) throw new Exception("Columna repetida "+col+" en "+ruta);
   t.Cabecera=c.ToArray();
   List<string> fila; int numero=1;
   while((fila=LeerFila(lector))!=null) {
    numero++;
    if(fila.Count!=c.Count) throw new Exception("Columnas diferentes en "+ruta+" fila "+numero);
    int id; bool eliminado;
    if(!int.TryParse(fila[0].Trim(),NumberStyles.None,CultureInfo.InvariantCulture,out id)||id<1||!bool.TryParse(fila[1].Trim(),out eliminado)) throw new Exception("ID/estado invalido en "+ruta+" fila "+numero);
    var datos=new Dictionary<string,string>(StringComparer.Ordinal);
    var sb=new StringBuilder(); sb.Append(eliminado?'1':'0');
    for(int i=2;i<c.Count;i++) { datos.Add(c[i],fila[i]); sb.Append('|').Append(fila[i].Length).Append(':').Append(fila[i]); }
    if(t.Filas.ContainsKey(id)) throw new Exception("ID duplicado en "+ruta+": "+id);
    t.Filas.Add(id,new Registro { Id=id, Eliminado=eliminado, Datos=datos, Firma=sb.ToString() });
   }
  }
  return t;
 }

 static List<string> LeerFila(TextReader r) {
  var campos=new List<string>(); var actual=new StringBuilder();
  bool comillas=false,inicio=true,cerrado=false;
  while(true) {
   int val=r.Read();
   if(val<0) { if(comillas) throw new Exception("CSV truncado dentro de comillas"); if(inicio) return null; campos.Add(actual.ToString()); return campos; }
   char ch=(char)val; inicio=false;
   if(comillas) {
    if(ch=='"') { if(r.Peek()=='"') { r.Read(); actual.Append('"'); } else { comillas=false; cerrado=true; } }
    else actual.Append(ch);
   }
   else if(ch==',') { campos.Add(actual.ToString()); actual.Length=0; cerrado=false; }
   else if(ch=='\r'||ch=='\n') { if(ch=='\r'&&r.Peek()=='\n') r.Read(); campos.Add(actual.ToString()); return campos; }
   else if(ch=='"'&&actual.Length==0&&!cerrado) comillas=true;
   else if(cerrado) throw new Exception("Caracter inesperado despues de comillas");
   else actual.Append(ch);
  }
 }

 // ---- Utilidades de sistema (iguales a HappyAuto) ----
 static bool DriveExists(string drive) { foreach(string s in Directory.GetLogicalDrives()) if(s.Equals(drive,StringComparison.OrdinalIgnoreCase)) return true; return false; }

 static HashSet<Guid> ListShadows() {
  string s=RunProcess("vssadmin.exe","list shadows /for=F:",60000,true);
  var set=new HashSet<Guid>();
  foreach(string line in s.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries))
   if(Regex.IsMatch(line,@"(?:Id\.\s*de\s*instant[aá]neas|Shadow\s+Copy\s+ID)\s*:",RegexOptions.IgnoreCase)) {
    Match m=Regex.Match(line,@"\{([0-9a-fA-F-]{36})\}"); if(m.Success) set.Add(new Guid(m.Groups[1].Value));
   }
  return set;
 }

 static string RunProcess(string exe,string arguments,int maxMs,bool allowEmptyVss=false) {
  Log("PROCESO "+Path.GetFileName(exe));
  var psi=new ProcessStartInfo(exe,arguments) { UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true };
  var output=new StringBuilder(); var errors=new StringBuilder();
  using(Process p=new Process()) {
   p.StartInfo=psi;
   p.OutputDataReceived+=(sender,e)=>{ if(e.Data!=null) lock(output) output.AppendLine(e.Data); };
   p.ErrorDataReceived+=(sender,e)=>{ if(e.Data!=null) lock(errors) errors.AppendLine(e.Data); };
   if(!p.Start()) throw new Exception("No inicia "+exe);
   p.BeginOutputReadLine(); p.BeginErrorReadLine();
   if(!p.WaitForExit(maxMs)) { try { p.Kill(); } catch {} throw new Exception("TIMEOUT "+exe); }
   p.WaitForExit();
   string data=output.ToString()+errors.ToString();
   if(p.ExitCode!=0) {
    bool noShadows=allowEmptyVss && exe.Equals("vssadmin.exe",StringComparison.OrdinalIgnoreCase)
      && ((data.IndexOf("elemento",StringComparison.OrdinalIgnoreCase)>=0 && data.IndexOf("criterios",StringComparison.OrdinalIgnoreCase)>=0)
          || data.IndexOf("No items found that satisfy the query",StringComparison.OrdinalIgnoreCase)>=0);
    if(noShadows) { Log("VSS: ninguna instantanea presente (codigo de salida 1 esperado)."); return data; }
    Log(data.Length>3000?data.Substring(0,3000):data);
    throw new Exception("Proceso fallo "+exe+" codigo="+p.ExitCode);
   }
   return data;
  }
 }

 static void Log(string s) { Console.WriteLine(s); if(LogFile!=null) File.AppendAllText(LogFile,DateTime.Now.ToString("s")+" "+s+Environment.NewLine,Encoding.UTF8); }
}
