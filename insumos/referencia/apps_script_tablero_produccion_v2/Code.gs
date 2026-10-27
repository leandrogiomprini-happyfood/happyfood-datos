/**
 * HAPPY FOOD — Tablero de produccion y stock v2 (oct-2026, Google Apps Script)
 * ==================================================================
 * Lee los Sheets EN VIVO con acceso autenticado (sin fotos comprimidas ni
 * respaldos en Drive: eso fue lo que rompio la version anterior).
 * Stock desde "Control de stock-KG" (el archivo vigente del equipo). Los pedidos
 * pendientes se pueden TILDAR/DESTILDAR en la pestaña Pendientes para
 * incluirlos o no como "comprometidos". El plan (disponible, estado,
 * producir) se recalcula al instante en el navegador.
 *  - "Guardar selección" persiste la elección en el servidor: al volver
 *    a abrir, los destildados siguen destildados (para todos los usuarios).
 *  - Sin guardar, la simulación dura lo que dura la pestaña abierta.
 * Instalar como PROYECTO NUEVO en script.google.com (no pisar el original).
 *
 * Metodología: idéntica al tablero original (agosto 2026).
 */

// ========================= CONFIGURACIÓN =========================
var CONFIG = {
  PEDIDOS_ID: '1Sr_ep7G2cpRSeH3YNMm0lzaFlHGuMk8Mio6qHb3Le_Q',
  // Stock: "Control de stock-KG" (el archivo que carga el equipo; el Sheet
  // "Happy Food - Stock" viejo quedo congelado en agosto 2026 y NO se usa mas).
  STOCK_ID:   '1Kv0DQjxqwH2zkEiKg1Izp1t-Jl2zuac2xi4ExRKcmQY',
  ALLOWED_EMAILS: [],
  NIVEL_SERVICIO_Z: 1.6449,
  COBERTURA_SEM: 2.0,
  VU_PCT: 0.40,
  DIAS_PENDIENTES: 60,
  SEM_CLIENTE_NUEVO: 12
};

var DERIVED = {
  3002:3000, 3006:3000, 3012:3010, 3016:3010, 3022:3020, 3026:3020, 3036:3030,
  3042:3040, 3046:3040, 3052:3050, 3056:3050, 3072:3070, 3076:3070,
  3082:3080, 3086:3080, 3092:3090, 3096:3090, 3102:3100, 3106:3100, 3116:3110
};
var SUPER_BAND = {3001:1, 3011:1, 3021:1, 3041:1, 3051:1, 3101:1};

// ========================= WEB APP =========================
function doGet(e) {
  var user = Session.getActiveUser().getEmail() || '';
  if (CONFIG.ALLOWED_EMAILS.length &&
      CONFIG.ALLOWED_EMAILS.map(function(em){return em.toLowerCase();}).indexOf(user.toLowerCase()) < 0) {
    return HtmlService.createHtmlOutput(
      '<p style="font-family:sans-serif">Acceso no autorizado para ' + (user || '(cuenta sin identificar)') +
      '. Pedile a Cuci que agregue tu email en la configuración.</p>');
  }
  // Diagnostico: URL/exec?debug=1 -> texto plano con el estado real del servidor
  if (e && e.parameter && e.parameter.debug) {
    var t = new Date().getTime(), txt;
    try {
      var json = getData();
      var o = JSON.parse(json);
      txt = 'OK en ' + (new Date().getTime() - t) + ' ms - ' + json.length + ' bytes\n' +
        'plan: ' + o.plan.length + ' SKUs - pendientes: ' + o.pend.length +
        ' - clientes: ' + o.clientes.length + ' - stockRows: ' + o.stockRows.length +
        ' - semanas: ' + o.serie.length + '\nultima orden: ' + o.ultimaOrden +
        ' - excluidos guardados: ' + (o.excluded ? o.excluded.length : 0);
    } catch (err) {
      txt = 'ERROR: ' + err.message + '\n' + (err.stack || '');
    }
    return ContentService.createTextOutput(txt).setMimeType(ContentService.MimeType.TEXT);
  }
  return HtmlService.createTemplateFromFile('Index').evaluate()
    .setTitle('Happy Food — Producción y stock')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

function getData() {
  var ped = SpreadsheetApp.openById(CONFIG.PEDIDOS_ID);
  var stk = SpreadsheetApp.openById(CONFIG.STOCK_ID);
  var ords = mustSheet_(ped, 'ORDENES', 'pedidos');
  var det = mustSheet_(ped, 'DETALLE', 'pedidos');
  var prods = mustSheet_(ped, 'PRODUCTOS', 'pedidos');
  var cd = sheetValues_(stk, 'STOCK CD') || sheetValues_(stk, 'STOCK_CD-VARIOS VENC.');
  var pl = sheetValues_(stk, 'STOCK PLANTA') || sheetValues_(stk, 'STOCK_Planta');
  var tr = sheetValues_(stk, 'STOCK TRANSITO') || sheetValues_(stk, 'STOCK_Transito');
  if (!cd && !pl && !tr) {
    throw new Error('No encontre ninguna hoja de stock en "Control de stock-KG". Hojas disponibles: ' +
      stk.getSheets().map(function(s){ return '"' + s.getName() + '"'; }).join(', '));
  }
  var stockTables = [
    { dep: 'CD', rows: cd }, { dep: 'Planta', rows: pl }, { dep: 'Transito', rows: tr }
  ];
  var out = computeAll(ords, det, prods, stockTables, new Date());
  out.excluded = loadExcluded_();
  out.ts = Utilities.formatDate(new Date(), 'America/Argentina/Cordoba', "dd/MM/yyyy HH:mm");
  return JSON.stringify(out);
}

// --- persistencia de la selección (compartida por todos los usuarios del simulador) ---
function loadExcluded_() {
  try { return JSON.parse(PropertiesService.getScriptProperties().getProperty('EXCLUDED_PEND') || '[]'); }
  catch (e) { return []; }
}
// Recibe un array JSON de claves "op|cod" de las líneas pendientes EXCLUIDAS.
function saveExcluded(json) {
  var arr;
  try { arr = JSON.parse(json); } catch (e) { throw new Error('Selección inválida.'); }
  if (!(arr instanceof Array) || arr.length > 2000) throw new Error('Selección inválida.');
  arr = arr.filter(function(k){ return typeof k === 'string' && k.length < 30; });
  PropertiesService.getScriptProperties().setProperty('EXCLUDED_PEND', JSON.stringify(arr));
  return arr.length;
}

function sheetValues_(ss, name) {
  var sheets = ss.getSheets();
  for (var i = 0; i < sheets.length; i++) {
    if (sheets[i].getName().trim() === name.trim()) {
      return sheets[i].getDataRange().getValues();
    }
  }
  return null;
}

// Igual que sheetValues_ pero corta con un error claro si la hoja no existe.
function mustSheet_(ss, name, cual) {
  var v = sheetValues_(ss, name);
  if (!v) throw new Error('Falta la hoja "' + name + '" en el Sheet de ' + cual +
    '. Hojas disponibles: ' + ss.getSheets().map(function(s){ return '"' + s.getName() + '"'; }).join(', '));
  if (v.length < 2) throw new Error('La hoja "' + name + '" esta vacia.');
  return v;
}

// ---- Pruebas desde el editor (elegir la funcion arriba y Ejecutar), sin implementar ----
function testGetData() {
  var t = new Date().getTime();
  var o = JSON.parse(getData());
  Logger.log('OK en %s ms', new Date().getTime() - t);
  Logger.log('plan: %s SKUs - pendientes: %s - clientes: %s - stockRows: %s - ultima orden: %s',
    o.plan.length, o.pend.length, o.clientes.length, o.stockRows.length, o.ultimaOrden);
}
function testHojas() {
  [['PEDIDOS', CONFIG.PEDIDOS_ID], ['STOCK', CONFIG.STOCK_ID]].forEach(function(par) {
    var ss = SpreadsheetApp.openById(par[1]);
    Logger.log('%s - hojas: %s', par[0],
      ss.getSheets().map(function(s){ return '"' + s.getName() + '"'; }).join(', '));
  });
}

// ========================= MOTOR DE CÁLCULO (puro, testeable) =========================
function computeAll(ords, det, prods, stockTables, today) {
  var t0 = new Date(today.getFullYear(), today.getMonth(), today.getDate());

  // ---------- maestro de productos ----------
  var ph = headerMap_(prods[0]);
  var master = {};
  for (var i = 1; i < prods.length; i++) {
    var r = prods[i];
    var cod = toInt_(r[ph['CODIGO']]);
    if (!cod) continue;
    master[cod] = {
      desc: String(r[ph['PRODUCTO']] || ''),
      estado: String(r[ph['ESTADO']] || '').trim(),
      unidad: String(r[ph['UNIDAD']] || '').trim(),
      vu: toNum_(r[ph['VU (días)']]) || null,
      polAct: (r[ph['POLÍTICA']] === '' || r[ph['POLÍTICA']] == null) ? null : toNum_(r[ph['POLÍTICA']]),
      kg: parseKg_(String(r[ph['PRODUCTO']] || ''))
    };
  }
  if (master[3153]) master[3153].kg = 1.4;
  if (master[3173]) master[3173].kg = 1.4;

  var FACTOR = {};
  Object.keys(DERIVED).forEach(function(d) {
    var m = master[d] ? master[d].desc.toUpperCase().match(/[X]\s*(\d+)\s*(UNID|UN\b|UND)/) : null;
    FACTOR[d] = m ? parseInt(m[1], 10) / 144 : (String(d).slice(-1) === '6' ? 36/144 : 24/144);
  });

  var universe = Object.keys(master).map(Number).filter(function(c) {
    return c >= 3000 && master[c].estado === 'VIGENTE' &&
      (master[c].unidad === 'Bulto' || master[c].unidad.indexOf('Caja') === 0);
  });

  // ---------- órdenes ----------
  var oh = headerMap_(ords[0]);
  var OM = {};
  for (var i = 1; i < ords.length; i++) {
    var r = ords[i];
    var n = toInt_(r[oh['N°']]);
    if (!n) continue;
    var f = toDate_(r[oh['Fecha']]);
    if (!f) continue;
    OM[n] = { f: f, cli: String(r[oh['Cliente']] || '').trim(),
              tipo: String(r[oh['Tipo']] || '').trim(),
              estado: String(r[oh['Estado']] || '').trim() };
  }

  // ---------- detalle ----------
  var dh = headerMap_(det[0]);
  var lines = [];
  var pendLines = [];
  var limPend = new Date(t0.getTime() - CONFIG.DIAS_PENDIENTES * 864e5);
  for (var i = 1; i < det.length; i++) {
    var r = det[i];
    var op = toInt_(r[dh['N° OP']]), cod = toInt_(r[dh['Código']]);
    if (!op || !cod || !OM[op]) continue;
    var o = OM[op];
    var q = toNum_(r[dh['Cant. Solicitada']]);
    if (q > 0 && o.estado === 'Pendiente' && o.f >= limPend) {
      var base = DERIVED[cod] || cod;
      pendLines.push({ op: op, fecha: fmtD_(o.f), cli: o.cli, cod: cod,
        prod: (master[cod] ? master[cod].desc : '').slice(0, 55),
        sol: q, base: base, cb: round2_(q * (DERIVED[cod] ? FACTOR[cod] : 1)),
        key: op + '|' + cod });
    }
    if (['EXPO', 'FASON', 'Reclamo'].indexOf(o.tipo) >= 0) continue;
    if (o.cli.toUpperCase() === 'RECLAMO') continue;
    if (q <= 0) continue;
    lines.push({ op: op, cod: cod, q: q, f: o.f, cli: o.cli, tipo: o.tipo });
  }

  // ---------- matriz semanal ----------
  var w0 = monday_(lines.reduce(function(a, l) { return l.f < a ? l.f : a; }, lines[0].f));
  var wN = monday_(lines.reduce(function(a, l) { return l.f > a ? l.f : a; }, lines[0].f));
  var NW = Math.round((wN - w0) / 6048e5) + 1;
  var series = {}, totalSem = new Array(NW).fill(0);
  lines.forEach(function(l) {
    var ix = Math.round((monday_(l.f) - w0) / 6048e5);
    (series[l.cod] = series[l.cod] || new Array(NW).fill(0))[ix] += l.q;
    totalSem[ix] += l.q;
  });

  // ---------- stats + políticas por SKU ----------
  var BASES = {};
  Object.keys(DERIVED).forEach(function(d) { BASES[DERIVED[d]] = 1; });
  var vols = {};
  universe.forEach(function(c) { vols[c] = (series[c] || []).reduce(function(a, b) { return a + b; }, 0); });
  var ordered = universe.slice().sort(function(a, b) { return vols[b] - vols[a]; });
  var volSum = ordered.reduce(function(a, c) { return a + vols[c]; }, 0), acc = 0, ABC = {};
  ordered.forEach(function(c) { acc += vols[c]; ABC[c] = vols[c] ? (acc / volSum <= .8 ? 'A' : acc / volSum <= .95 ? 'B' : 'C') : '-'; });

  var skus = [];
  ordered.forEach(function(c) {
    var s;
    if (BASES[c]) {
      s = (series[c] || new Array(NW).fill(0)).slice();
      Object.keys(DERIVED).forEach(function(d) {
        if (DERIVED[d] === c && series[d]) for (var i = 0; i < NW; i++) s[i] += series[d][i] * FACTOR[d];
      });
    } else s = series[c];
    var dem = 0, sd = 0, p95 = 0;
    if (s && s.some(function(v) { return v > 0; })) {
      var first = s.findIndex(function(v) { return v > 0; });
      var act = s.slice(first);
      dem = 0.5 * mean_(act) + 0.5 * mean_(s.slice(-12));
      sd = stdS_(act);
      p95 = pctl_(act, 0.95);
    }
    var m = master[c], cap = (m.vu && dem) ? dem * (m.vu / 7) * CONFIG.VU_PCT : null;
    var prop = dem * CONFIG.COBERTURA_SEM + CONFIG.NIVEL_SERVICIO_Z * sd;
    var polMin = dem ? Math.ceil(cap != null ? Math.min(prop, cap) : prop) : 0;
    var cont = dem ? Math.ceil(cap != null ? Math.min(p95, cap) : p95) : 0;
    skus.push({ cod: c, desc: m.desc, abc: ABC[c],
      esquema: DERIVED[c] ? 'derived' : (BASES[c] ? 'base' : (SUPER_BAND[c] ? 'super' : 'std')),
      base: DERIVED[c] || null, kg: m.kg, vu: m.vu, polAct: m.polAct,
      dem: round2_(dem), polMin: polMin, cont: cont });
  });

  // ---------- modelo por cliente + E próx semana ----------
  var byCli = {}, opsCli = {};
  lines.forEach(function(l) {
    (byCli[l.cli] = byCli[l.cli] || []).push(l);
    (opsCli[l.cli] = opsCli[l.cli] || {})[l.op] = l.f;
  });
  var clientes = [], rate = {}, nOrd = {};
  Object.keys(byCli).forEach(function(cli) {
    var fs = Object.keys(opsCli[cli]).map(function(k) { return opsCli[cli][k]; }).sort(function(a, b) { return a - b; });
    var n = fs.length, hist = (t0 - fs[0]) / 6048e5, spanW = Math.max(4, hist);
    var rt = n / spanW, wks = Math.max(0, (t0 - fs[n - 1]) / 6048e5), cad = null;
    if (n >= 2) { var g = []; for (var i = 1; i < n; i++) g.push((fs[i] - fs[i - 1]) / 6048e5); cad = pctl_(g, 0.5); }
    var inact = wks > Math.max(6, cad ? 3 * cad : 6);
    if (inact) rt = 0;
    var nuevo = !inact && hist < CONFIG.SEM_CLIENTE_NUEVO;
    rate[cli] = rt; nOrd[cli] = n;
    var qty = {};
    byCli[cli].forEach(function(l) { qty[l.cod] = (qty[l.cod] || 0) + l.q; });
    var top = Object.keys(qty).sort(function(a, b) { return qty[b] - qty[a]; }).slice(0, 3).join('; ');
    clientes.push({ nombre: cli, tipo: byCli[cli][0].tipo, pedidos: n, ultimo: fmtD_(fs[n - 1]),
      semDesde: round1_(wks), semHist: round1_(hist), cadencia: cad != null ? round1_(cad) : null,
      p: round2_(inact ? 0 : 1 - Math.exp(-rt)),
      sit: inact ? 'INACTIVO' : (nuevo ? 'NUEVO' : (cad != null && wks >= cad ? 'POR PEDIR' : 'ACTIVO')), skus: top });
  });
  clientes.sort(function(a, b) { return b.p - a.p; });

  var pares = [], E = {}, pairAgg = {};
  lines.forEach(function(l) {
    if (l.cod < 3000) return;
    var k = l.cli + '|' + l.cod;
    var a = pairAgg[k] = pairAgg[k] || { cli: l.cli, cod: l.cod, ops: {}, qty: 0, ult: l.f };
    a.ops[l.op] = 1; a.qty += l.q; if (l.f > a.ult) a.ult = l.f;
  });
  Object.keys(pairAgg).forEach(function(k) {
    var a = pairAgg[k], n = nOrd[a.cli], rt = rate[a.cli];
    var veces = Object.keys(a.ops).length;
    var e = rt > 0 ? rt * a.qty / n : 0;
    if (e > 0) E[a.cod] = (E[a.cod] || 0) + e;
    pares.push({ cli: a.cli, cod: a.cod, veces: veces, nped: n, pct: round2_(veces / n),
      qcp: round1_(a.qty / veces), ult: fmtD_(a.ult),
      pSku: round2_(rt > 0 ? 1 - Math.exp(-rt * veces / n) : 0), e: round1_(e) });
  });
  pares.sort(function(a, b) { return b.e - a.e; });

  // ---------- stock ----------
  var STOCK = {};
  stockTables.forEach(function(t) {
    if (!t.rows || t.rows.length < 2) return;
    // El encabezado puede no estar en la primera fila (en "Control de stock-KG" esta en la 3ra):
    // se busca la primera fila que tenga CODIGO y Total.
    var hi = -1, h = null;
    for (var j = 0; j < Math.min(10, t.rows.length); j++) {
      var hm = headerMap_(t.rows[j]);
      if (hm['CODIGO'] != null && hm['Total'] != null) { hi = j; h = hm; break; }
    }
    if (hi < 0) return;
    var iLim = h['Fecha limite de Entrega'];
    for (var i = hi + 1; i < t.rows.length; i++) {
      var r = t.rows[i], cod = toInt_(r[h['CODIGO']]);
      if (!cod) continue;
      var tot = toNum_(r[h['Total']]);
      var fl = iLim != null ? toDate_(r[iLim]) : null;
      var a = STOCK[cod] = STOCK[cod] || { cd: 0, pl: 0, tr: 0, tot: 0, nod: 0, r14: 0 };
      a.tot += tot;
      if (t.dep === 'CD') a.cd += tot; else if (t.dep === 'Planta') a.pl += tot; else a.tr += tot;
      if (fl && fl < t0) a.nod += tot;
      else if (fl && fl <= new Date(t0.getTime() + 14 * 864e5)) a.r14 += tot;
    }
  });
  Object.keys(STOCK).forEach(function(c) { STOCK[c].util = STOCK[c].tot - STOCK[c].nod; });

  var SEMI = {};
  Object.keys(STOCK).map(Number).forEach(function(c) {
    if (c < 2000 || c > 2999 || !master[c + 1000]) return;
    var d = master[c + 1000].desc.toUpperCase();
    var m = d.match(/[X]\s*(\d+)\s*BAND/) || d.match(/[X]\s*(\d+)\s*(UNID|UND|UN\b)/);
    if (!m) return;
    var div = parseInt(m[1], 10);
    SEMI[c + 1000] = { semi: c, unid: STOCK[c].tot, div: div, equiv: round1_(STOCK[c].tot / div) };
  });

  // ---------- plan (los comprometidos los aplica el NAVEGADOR según lo tildado) ----------
  // Acá se publican los ingredientes por SKU; comp/disp/estado/producir se calculan
  // en Index.html para que el tildado de pendientes recalcule al instante.
  var plan = [];
  skus.forEach(function(s) {
    var st = STOCK[s.cod] || { util: 0 };
    var util = (st.util || 0) + (SEMI[s.cod] ? SEMI[s.cod].equiv : 0);
    var e = s.esquema === 'derived' ? round1_(E[s.cod] || 0) :
      round1_((E[s.cod] || 0) + Object.keys(DERIVED).reduce(function(a, d) {
        return DERIVED[d] === s.cod ? a + (E[d] || 0) * FACTOR[d] : a; }, 0));
    plan.push({ cod: s.cod, desc: s.desc, abc: s.abc, esquema: s.esquema, base: s.base,
      polAct: s.polAct, polMin: s.polMin, cont: s.cont, dem: s.dem,
      util: round1_(util), e: e, kgU: s.kg });
  });

  var stockRows = Object.keys(STOCK).map(Number).sort(function(a, b) { return a - b; })
    .filter(function(c) { return STOCK[c].tot || STOCK[c].nod; })
    .map(function(c) {
      var s = STOCK[c], conv = null;
      Object.keys(SEMI).forEach(function(t) { if (SEMI[t].semi === c) conv = { target: +t, div: SEMI[t].div, equiv: SEMI[t].equiv }; });
      var recibe = SEMI[c] ? { semi: SEMI[c].semi, equiv: SEMI[c].equiv } : null;
      return { cod: c, desc: master[c] ? master[c].desc.slice(0, 55) : '',
        cd: s.cd, pl: s.pl, tr: s.tr, tot: s.tot, nod: s.nod, util: s.util,
        conv: conv, recibe: recibe };
    });

  var serie = totalSem.map(function(v, i) {
    var dt = new Date(w0.getTime() + i * 6048e5);
    return { sem: pad_(dt.getDate()) + '/' + pad_(dt.getMonth() + 1), v: v };
  });

  var maxF = lines.reduce(function(a, l) { return l.f > a ? l.f : a; }, lines[0].f);
  return { plan: plan, pend: pendLines, clientes: clientes, pares: pares,
    stockRows: stockRows, serie: serie, ultimaOrden: fmtD_(maxF) };
}

// ========================= HELPERS =========================
// Normaliza espacios invisibles con ESCAPES EXPLICITOS (NBSP y similares): si el
// carácter va literal en el código, un copiar/pegar lo degrada y deja de andar.
function headerMap_(row) {
  var m = {};
  for (var i = 0; i < row.length; i++) {
    var k = String(row[i] == null ? '' : row[i])
      .replace(/[\u00A0\u2007\u202F]/g, ' ')
      .replace(/[\u200B\uFEFF]/g, '')
      .trim();
    if (k && m[k] == null) m[k] = i;
  }
  return m;
}
function toInt_(v) { var n = parseInt(v, 10); return isNaN(n) ? 0 : n; }
function toNum_(v) {
  if (typeof v === 'number') return v;
  var s = String(v == null ? '' : v).trim();
  if (!s || s === '-') return 0;
  var n = parseFloat(s.replace(/\./g, '').replace(',', '.'));
  return isNaN(n) ? 0 : n;
}
function toDate_(v) {
  if (v instanceof Date && !isNaN(v)) return v;
  var m = String(v == null ? '' : v).match(/(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  return m ? new Date(+m[3], +m[2] - 1, +m[1]) : null;
}
function parseKg_(desc) {
  var d = desc.toUpperCase(), g = null;
  var m = d.match(/PAQ\.?\s*(\d+)\s*GR/) || d.match(/(\d+)\s*GR/);
  if (m) g = parseInt(m[1], 10);
  if (g == null) {
    if (d.indexOf('BOC') >= 0) g = 40;
    else if (d.indexOf('SOJA') >= 0) g = 45;
    else if (d.indexOf('ALF') >= 0) g = 50;
    else if (d.indexOf('GALL') >= 0 && d.indexOf('FAMILIAR') < 0 && d.indexOf('MARINERA') < 0) g = 44;
  }
  var n = null, mult = 1;
  m = d.match(/[X]\s*(\d+)\s*BAND/);
  if (m) { n = parseInt(m[1], 10); mult = 3; }
  else { m = d.match(/[X]?\s*(\d+)\s*(UNID|UND|UN\b|U\b)/); if (m) n = parseInt(m[1], 10); }
  return (n && g) ? Math.round(n * mult * g) / 1000 : null;
}
function monday_(d) {
  var x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  x.setDate(x.getDate() - ((x.getDay() + 6) % 7));
  return x;
}
function mean_(a) { return a.length ? a.reduce(function(s, x) { return s + x; }, 0) / a.length : 0; }
function stdS_(a) {
  if (a.length < 2) return 0;
  var m = mean_(a);
  return Math.sqrt(a.reduce(function(s, x) { return s + (x - m) * (x - m); }, 0) / (a.length - 1));
}
function pctl_(arr, q) {
  var a = arr.slice().sort(function(x, y) { return x - y; }), n = a.length;
  if (!n) return 0; if (n === 1) return a[0];
  var h = (n - 1) * q, lo = Math.floor(h);
  return a[lo] + (a[Math.min(lo + 1, n - 1)] - a[lo]) * (h - lo);
}
function fmtD_(d) { return pad_(d.getDate()) + '/' + pad_(d.getMonth() + 1) + '/' + String(d.getFullYear()).slice(2); }
function pad_(n) { return (n < 10 ? '0' : '') + n; }
function round1_(v) { return Math.round(v * 10) / 10; }
function round2_(v) { return Math.round(v * 100) / 100; }
