/**
 * Tablero "Cobertura de Insumos Happy Food" — publicación web con Apps Script.
 *
 * Cómo funciona:
 *   El proceso de Claude deja en Drive un archivo JSON con los datos de la última
 *   corrida. Esta página lo lee y lo muestra. No calcula nada: sólo publica.
 *
 * Antes de usar: revisá abajo el nombre del archivo de datos y los correos que pueden entrar.
 */

// ---- CONFIGURACIÓN ---------------------------------------------------------

// Los datos llegan a Drive en archivos que se llaman
// tablero_insumos.part1de3.b64, tablero_insumos.part2de3.b64, etc.
var PREFIJO = 'tablero_insumos.part';

// Quiénes pueden ver el tablero
var DOMINIOS_PERMITIDOS = ['happyfood.com.ar'];
var CORREOS_PERMITIDOS  = ['leandrogiomprini@gmail.com'];

// ---- FIN DE LA CONFIGURACIÓN -----------------------------------------------

function doGet() {
  var mail = (Session.getActiveUser().getEmail() || '').toLowerCase();
  if (!permitido(mail)) {
    return HtmlService.createHtmlOutput(
      '<div style="font:16px/1.5 system-ui;padding:40px;max-width:40em">' +
      '<h2 style="font:600 22px system-ui">Sin acceso</h2>' +
      '<p>La cuenta <b>' + escapar(mail || 'sin identificar') + '</b> no tiene permiso para ver este tablero.</p>' +
      '<p>Entrá con tu cuenta de Happy Food, o pedile a Leandro que agregue tu correo.</p></div>')
      .setTitle('Cobertura de Insumos Happy Food');
  }

  var t = HtmlService.createTemplateFromFile('Index');
  t.datos = leerDatos();
  return t.evaluate()
    .setTitle('Cobertura de Insumos Happy Food')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function permitido(mail) {
  if (!mail) return false;                       // sin sesión de Google
  var dom = mail.split('@')[1] || '';
  if (DOMINIOS_PERMITIDOS.indexOf(dom) >= 0) return true;
  return CORREOS_PERMITIDOS.map(function (m) { return m.toLowerCase(); }).indexOf(mail) >= 0;
}

/**
 * Los datos viajan partidos en varios archivos de texto (base64 de un .gz),
 * porque el proceso que los sube no puede mandar un archivo grande de una vez.
 * Acá se juntan, se descomprimen y se devuelven como JSON.
 */
function leerDatos() {
  var cache = CacheService.getScriptCache();
  var firma = null, partes = {}, total = 0;
  try {
    var it = DriveApp.searchFiles('title contains "' + PREFIJO + '" and trashed = false');
    var archivos = [];
    while (it.hasNext()) archivos.push(it.next());
    if (!archivos.length) return 'null';
    // se queda con el juego más nuevo: parte1deN, parte2deN, ...
    archivos.sort(function (a, b) { return b.getLastUpdated() - a.getLastUpdated(); });
    var m = archivos[0].getName().match(/part(\d+)de(\d+)/);
    if (!m) return 'null';
    total = Number(m[2]);
    firma = String(archivos[0].getLastUpdated().getTime());
    var cacheado = cache.get('tablero_' + firma);
    if (cacheado) return cacheado;
    for (var i = 0; i < archivos.length; i++) {
      var mm = archivos[i].getName().match(/part(\d+)de(\d+)/);
      if (!mm || Number(mm[2]) !== total) continue;
      var n = Number(mm[1]);
      if (!partes[n]) partes[n] = archivos[i].getBlob().getDataAsString('UTF-8').replace(/\s/g, '');
    }
    var b64 = '';
    for (var k = 1; k <= total; k++) {
      if (!partes[k]) return 'null';           // falta una parte: mejor no mostrar datos a medias
      b64 += partes[k];
    }
    var gz = Utilities.newBlob(Utilities.base64Decode(b64), 'application/x-gzip', 'datos.gz');
    var txt = Utilities.ungzip(gz).getDataAsString('UTF-8');
    if (txt.length < 100000) cache.put('tablero_' + firma, txt, 600);
    return txt;
  } catch (e) {
    return 'null';
  }
}

/** Para probar desde el editor: muestra cuántos insumos trae el archivo. */
function probarDatos() {
  var d = JSON.parse(leerDatos());
  Logger.log(d ? d.insumos.length + ' insumos · conteo ' + d.meta.ultimo_conteo : 'no se pudieron leer los datos');
}

function escapar(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
