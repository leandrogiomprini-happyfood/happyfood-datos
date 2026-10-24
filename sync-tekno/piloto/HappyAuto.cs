using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using System.Linq;

// Happy Food - Windows Server 2008 R2, .NET Framework 4.8.
// Estado persistente y fail-closed; nunca modifica Tecno. Sin reintentos de escrituras dudosas.
class HappyAuto {
 const string Root=@"C:\HAPPY_EXTRACTOR";
 const string Sync=Root+@"\SYNC";
 const string State=Sync+@"\AUTO_ESTADO";
 const string Baseline=State+@"\BASE_CONFIRMADA";
 const string LockPath=State+@"\en_ejecucion.lock";
 const string Block=State+@"\REQUIERE_REVISION.txt";
 const string Enabled=State+@"\AUTORIZACION_AUTOMATICA.txt";
 const string Token="AUTORIZO_SYNC_AUTOMATICA_CADA_10_MIN";
 const string Endpoint="https://igcewbadhejtesbogewm.supabase.co/functions/v1/happyfood-sync";
 const string Extractor=Root+@"\happy_extractor_v1\Extractor.exe";
 const string Comparator=Sync+@"\HappyControlIncremental.exe";
 const string Original= @"X:\TEKNO\ssoft.hap\DATOS\";
 const string Source=Root+@"\CSV_20261022";
 const string HashVentas="5c8bc2d8746bc09002ed7db41d87aee1ad505975386d748bf65f0a6d8f52bde8";
 const string HashDetalle="699cb89c43285d0c9bc94dd7a0bb1a25aebed58520a3ac45e13db8f65b6d5ca9";
 static string LogFile;
 const string PingFile=State+@"\healthcheck_url.txt"; // una linea: https://hc-ping.com/<uuid>
 static bool Scheduled=false;
 static readonly JavaScriptSerializer J=new JavaScriptSerializer { MaxJsonLength=int.MaxValue, RecursionLimit=100 };
 static int Main(string[] args) {
  try {
   Directory.CreateDirectory(State);
   if(args.Length!=1) throw new Exception("Uso: HappyAuto.exe preparar | probar | sincronizar | estado");
   if(args[0]=="estado") { Console.WriteLine("BASE: "+Directory.Exists(Baseline)+" / BLOQUEADO: "+File.Exists(Block)+" / AUTORIZADO: "+File.Exists(Enabled)); return 0; }
   using(var l=new FileStream(LockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None)) {
    if(args[0]=="preparar") { Prepare(); return 0; }
    if(args[0]!="probar" && args[0]!="sincronizar") throw new Exception("Modo invalido.");
    bool write=args[0]=="sincronizar";
    Scheduled=write;
    if(!Directory.Exists(Baseline)) throw new Exception("Falta BASE_CONFIRMADA. Ejecutar preparar primero.");
    if(File.Exists(Block)) throw new Exception("DETENIDO: existe REQUIERE_REVISION.txt. No reintentar sin conciliar Supabase.");
    if(write && (!File.Exists(Enabled) || File.ReadAllText(Enabled).Trim()!=Token)) throw new Exception("Escritura automatica NO autorizada. Falta archivo de habilitacion.");
    Run(write);
   }
   if(Scheduled) Ping("");
   return 0;
  } catch(Exception ex) { Console.WriteLine("DETENIDO: "+ex.Message); if(LogFile!=null) try{ File.AppendAllText(LogFile,"ERROR "+DateTime.Now.ToString("s")+" "+ex.ToString()+Environment.NewLine);}catch{} if(Scheduled) Ping("/fail"); return 1; }
 }
 // Aviso externo (Healthchecks.io). Nunca interrumpe ni cambia el resultado de la sincronizacion.
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
 static void Prepare() {
  if(Directory.Exists(Baseline)) throw new Exception("La base ya existe. No se sobreescribe.");
  VerifyHash(Path.Combine(Source,"movivent.csv"),HashVentas);
  VerifyHash(Path.Combine(Source,"DETAVENT.csv"),HashDetalle);
  Directory.CreateDirectory(Baseline);
  try { File.Copy(Path.Combine(Source,"movivent.csv"),Path.Combine(Baseline,"movivent.csv")); File.Copy(Path.Combine(Source,"DETAVENT.csv"),Path.Combine(Baseline,"DETAVENT.csv")); }
  catch { Directory.Delete(Baseline,true); throw; }
  File.WriteAllText(Path.Combine(State,"base_inicial.txt"),"Extraccion 22/10/2026 confirmada en Supabase: ventas 6060; detalle 39982. Inicializada "+DateTime.Now.ToString("s"),Encoding.UTF8);
  Console.WriteLine("BASE INICIALIZADA: CSV_20261022, hashes verificados. No se escribio en Supabase.");
 }
 static void Run(bool write) {
  if(!File.Exists(Extractor)||!File.Exists(Comparator)) throw new Exception("Falta extractor o comparador existente.");
  string stamp=DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
  string run=Path.Combine(State,"EJECUCIONES",stamp);
  Directory.CreateDirectory(run); LogFile=Path.Combine(run,"ejecucion.log");
  string dbfs=Path.Combine(run,"DBF"), csv=Path.Combine(run,"CSV"), changes=Path.Combine(run,"CAMBIOS");
  Directory.CreateDirectory(dbfs); Directory.CreateDirectory(csv);
  Log("INICIO modo="+(write?"SINCRONIZAR":"SOLO_PRUEBA")+" run="+run);
  Guid shadow=Guid.Empty;
  HashSet<Guid> before=ListShadows();
  if(DriveExists(@"X:\")) throw new Exception("La unidad X: esta ocupada. No se crea VSS.");
  try {
   string script=Path.Combine(run,"crear_vss.txt");
   File.WriteAllText(script,"set context persistent nowriters\r\nadd volume F: alias happyf\r\ncreate\r\nexpose %happyf% X:\r\n",Encoding.ASCII);
   RunProcess("diskshadow.exe","/s \""+script+"\"",120000);
   var after=ListShadows(); after.ExceptWith(before);
   if(after.Count!=1) throw new Exception("No se pudo identificar una unica nueva instantanea VSS. Limpieza manual necesaria. Cantidad nueva="+after.Count);
   shadow=after.First();
   Log("VSS creada, ID="+shadow.ToString("D"));
   if(!DriveExists(@"X:\")) throw new Exception("La instantanea no quedo expuesta como X:");
   CopyDbf("MOVIVENT.DBF",dbfs); CopyDbf("DETAVENT.DBF",dbfs);
  } finally {
   // Si DiskShadow fallo antes de identificar ID, intentar descubrir un unico ID nuevo.
   if(shadow==Guid.Empty) {
    try { var fresh=ListShadows(); fresh.ExceptWith(before); if(fresh.Count==1) shadow=fresh.First(); } catch {} 
   }
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
  RunProcess(Extractor,"\""+dbfs+"\" \""+csv+"\"",180000);
  VerifyCsv(csv);
  RunProcess(Comparator,"\""+Baseline+"\" \""+csv+"\" \""+changes+"\"",180000);
  var batches=new List<string>();
  batches.AddRange(Directory.GetFiles(changes,"ventas_cambio_*.json").OrderBy(x=>x,StringComparer.Ordinal));
  batches.AddRange(Directory.GetFiles(changes,"ventas_detalle_cambio_*.json").OrderBy(x=>x,StringComparer.Ordinal));
  foreach(string file in batches) CheckIdentity(file,Baseline);
  Log("PREPARACION_OK lotes="+batches.Count+" (ventas primero, detalles despues)");
  if(!write) { Log("PRUEBA CORRECTA: SIN CONEXION NI ESCRITURA. Ver RESUMEN_CAMBIOS.txt"); return; }
  if(batches.Count==0) { Promote(csv); Log("SIN CAMBIOS. BASE AVANZADA."); return; }
  File.WriteAllText(Block,"SINCRONIZACION EN CURSO o INCIERTA. Run="+run+". No borrar sin conciliacion SQL.",Encoding.UTF8);
  foreach(string file in batches) {
   string sha=Hash(file); Log("START "+Path.GetFileName(file)+" SHA256="+sha);
   Send(file);
   Log("OK "+Path.GetFileName(file)+" SHA256="+sha);
  }
  Log("TODOS_LOS_LOTES_CONFIRMADOS: "+batches.Count);
  Promote(csv);
  Log("BASE_AVANZADA. CICLO COMPLETO.");
  File.Delete(Block);
 }
 static void VerifyCsv(string csv) {
  foreach(string f in new[]{"movivent.csv","DETAVENT.csv"}) {
   string p=Path.Combine(csv,f); if(!File.Exists(p)||new FileInfo(p).Length<100) throw new Exception("CSV faltante/vacio: "+p);
  }
 }
 static void Promote(string csv) {
  // Renombrado de directorios en el mismo volumen; recuperacion fail-closed con bloqueo persistente.
  string previous=Path.Combine(State,"BASE_ANTERIOR");
  if(Directory.Exists(previous)) Directory.Delete(previous,true);
  Directory.Move(Baseline,previous);
  try { Directory.Move(csv,Baseline); }
  catch { Directory.Move(previous,Baseline); throw; }
 }
 static void CopyDbf(string file,string target) {
  string src=Path.Combine(Original,file),dest=Path.Combine(target,file);
  if(!File.Exists(src)) throw new Exception("DBF no hallado en VSS: "+src);
  File.Copy(src,dest,false); if(new FileInfo(dest).Length!=new FileInfo(src).Length) throw new Exception("Tamano DBF distinto: "+file);
  Log("COPIA_OK "+file+" bytes="+new FileInfo(dest).Length);
 }
 static bool DriveExists(string drive) { foreach(string s in Directory.GetLogicalDrives()) if(s.Equals(drive,StringComparison.OrdinalIgnoreCase))return true; return false; }
 static HashSet<Guid> ListShadows() {
  string s=RunProcess("vssadmin.exe","list shadows /for=F:",60000,true);
  var set=new HashSet<Guid>();
  var lines=s.Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries);
  foreach(string line in lines) if(Regex.IsMatch(line,@"(?:Id\.\s*de\s*instant[aá]neas|Shadow\s+Copy\s+ID)\s*:",RegexOptions.IgnoreCase)) {
    Match m=Regex.Match(line,@"\{([0-9a-fA-F-]{36})\}"); if(m.Success)set.Add(new Guid(m.Groups[1].Value));
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
   if(!p.WaitForExit(maxMs)) { try {p.Kill();}catch{} throw new Exception("TIMEOUT "+exe); }
   p.WaitForExit();
   string data=output.ToString()+errors.ToString();
   if(p.ExitCode!=0) {
    // Windows Server 2008 R2: vssadmin puede devolver codigo 1 si no existen instantaneas.
    // Aceptar SOLO esa respuesta conocida, nunca otros errores.
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
 static void CheckIdentity(string file,string baseDir) {
  var payload=J.Deserialize<Dictionary<string,object>>(File.ReadAllText(file,Encoding.UTF8));
  string table=Convert.ToString(payload["tabla"]);
  var regs=(IList)payload["registros"];
  if(regs.Count<1||regs.Count>100) throw new Exception("Tamano lote invalido: "+file);
  string csv=Path.Combine(baseDir,table=="ventas"?"movivent.csv":"DETAVENT.csv");
  string[] keys=table=="ventas"?new[]{"ORDEVENT","CODICOMP","NUMEVENT"}:new[]{"ORDEFINA","ORDECOMP"};
  // Campos de identidad conocidos por registro_origen; para nuevas filas basta comparar en siguiente ciclo.
  var identities=ReadIdentityCsv(csv,keys);
  foreach(object obj in regs) {
   var row=(Dictionary<string,object>)obj; int id=Convert.ToInt32(row["registro_origen"]);
   var data=(Dictionary<string,object>)row["datos"];
   string[] old;
   if(!identities.TryGetValue(id,out old))continue;
   for(int i=0;i<keys.Length;i++) if(old[i]!=Convert.ToString(data[keys[i]]).Trim()) throw new Exception("IDENTIDAD MODIFICADA: "+table+" ID="+id+" campo="+keys[i]+". Posible PACK o reasignacion. DETENIDO.");
  }
 }
 static Dictionary<int,string[]> ReadIdentityCsv(string p,string[] keys) {
  var res=new Dictionary<int,string[]>();
  using(var r=new StreamReader(p,Encoding.UTF8,true)) {
   var header=ReadCsvRow(r); if(header==null)throw new Exception("CSV base vacio");
   int[] index=keys.Select(k=>header.IndexOf(k)).ToArray();
   if(index.Any(x=>x<0))throw new Exception("Faltan claves comerciales en CSV: "+p);
   List<string> row;
   while((row=ReadCsvRow(r))!=null) { int id=int.Parse(row[0]); res.Add(id,index.Select(x=>row[x].Trim()).ToArray()); }
  }
  return res;
 }
 static List<string> ReadCsvRow(TextReader r) {
  var result=new List<string>();var b=new StringBuilder();bool quote=false,opened=false,closed=false;
  while(true) {int i=r.Read();if(i<0){if(quote)throw new Exception("CSV truncado");if(!opened)return null;result.Add(b.ToString());return result;}char c=(char)i;opened=true;
   if(quote) {if(c=='"'){if(r.Peek()=='"'){r.Read();b.Append('"');}else{quote=false;closed=true;}}else b.Append(c);}
   else if(c==','){result.Add(b.ToString());b.Length=0;closed=false;}
   else if(c=='\n'||c=='\r'){if(c=='\r'&&r.Peek()=='\n')r.Read();result.Add(b.ToString());return result;}
   else if(c=='"'&&b.Length==0&&!closed)quote=true;
   else if(closed)throw new Exception("CSV invalido");else b.Append(c);
  }
 }
 static void Send(string file) {
  var doc=J.Deserialize<Dictionary<string,object>>(File.ReadAllText(file,Encoding.UTF8));
  IList registros=(IList)doc["registros"]; int cnt=registros.Count;
  string table=Convert.ToString(doc["tabla"]);
  if(table!="ventas"&&table!="ventas_detalle")throw new Exception("Tabla inesperada");
  if(cnt<1||cnt>100)throw new Exception("Cantidad invalida");
  string keyPath=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"HappyFoodSync","credencial.dpapi");
  if(!File.Exists(keyPath))throw new Exception("DPAPI no existe para esta cuenta Windows. Verificar cuenta de tarea programada.");
  byte[] entropy=Encoding.UTF8.GetBytes("HappyFoodSync-Servidor-v1");
  string key=Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(keyPath),entropy,DataProtectionScope.CurrentUser));
  if(!key.StartsWith("sb_secret_",StringComparison.Ordinal))throw new Exception("Credencial inesperada");
  doc["accion"]="sincronizar_lote";doc["confirmar_escritura"]="ESCRIBIR_LOTE";
  byte[] bytes=Encoding.UTF8.GetBytes(J.Serialize(doc));
  ServicePointManager.SecurityProtocol=(SecurityProtocolType)3072;
  var req=(HttpWebRequest)WebRequest.Create(Endpoint);
  req.Method="POST";req.ContentType="application/json; charset=utf-8";req.Headers.Add("apikey",key);
  req.Timeout=90000;req.ReadWriteTimeout=90000;req.ContentLength=bytes.Length;
  using(Stream str=req.GetRequestStream())str.Write(bytes,0,bytes.Length);
  string response;
  using(var resp=(HttpWebResponse)req.GetResponse()) { if(resp.StatusCode!=HttpStatusCode.OK)throw new Exception("HTTP "+(int)resp.StatusCode);using(var rdr=new StreamReader(resp.GetResponseStream())) response=rdr.ReadToEnd(); }
  var reply=J.Deserialize<Dictionary<string,object>>(response);
  var sqlResponse=reply.ContainsKey("resultado_sql")?reply["resultado_sql"] as Dictionary<string,object>:null;
  if(!Equals(reply["ok"],true)||Convert.ToString(reply["tabla"])!=table||Convert.ToInt32(reply["recibidos"])!=cnt||sqlResponse==null||!Equals(sqlResponse["ok"],true)||Convert.ToInt32(sqlResponse["procesados"])!=cnt)throw new Exception("Respuesta SQL no confirmada; no reintentar sin conciliacion.");
 }
 static void VerifyHash(string p,string hash) { if(Hash(p)!=hash)throw new Exception("SHA256 no coincide: "+p); }
 static string Hash(string p) { using(var sha=SHA256.Create())using(var f=File.OpenRead(p))return BitConverter.ToString(sha.ComputeHash(f)).Replace("-","").ToLowerInvariant(); }
 static void Log(string s) {Console.WriteLine(s);if(LogFile!=null) File.AppendAllText(LogFile,DateTime.Now.ToString("s")+" "+s+Environment.NewLine,Encoding.UTF8);}
}
