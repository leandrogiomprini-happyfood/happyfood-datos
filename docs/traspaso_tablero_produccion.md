# Happy Food — Contexto del proyecto (traspaso)

Actualizado 22/10/2026 · Dueño: Cuci (Leandro Giomprini, leandrogiomprini@gmail.com / @happyfood.com.ar) · Happy Food: fábrica de alimentos sin gluten, Argentina.

Este documento resume el trabajo del proyecto "Estimación de la demanda y producción" para que cualquier otra conversación de Claude lo use como punto de partida.

## Qué se construyó

**Tablero de producción y stock** (Google Apps Script, web app — "tablero v2" del 16/10/2026): lee los Sheets en vivo con acceso autenticado, calcula demanda, políticas de stock, comprometidos y el plan semanal de producción. Instalado y funcionando en un proyecto de script.google.com de la cuenta leandrogiomprini@gmail.com. Incluye:

- Pestaña "Pendientes ✓": se tildan/destildan los pedidos pendientes que cuentan como comprometidos; el plan se recalcula al instante y la selección se persiste en el servidor (compartida entre usuarios).
- Diagnóstico: `?debug=1` al final de la URL /exec; funciones `testGetData` y `testHojas` ejecutables desde el editor sin reimplementar.
- Pestañas: Plan semanal, Pendientes ✓, Clientes, Cliente × SKU, Stock, Demanda histórica.

Entregables previos vigentes:
- Plan de Producción Sep–Oct 2026 (balance en kg): https://claude.ai/code/artifact/7fac3745-269c-4951-8c00-5f88e3d94e1a
- Manual del tablero: https://claude.ai/code/artifact/e02e30c9-71d0-465e-86c2-2238facdd96b — OJO: describe una versión anterior; las secciones "Política HappyFood" y "objetivo de toneladas" NO aplican al v2.

## Fuentes de datos (Google Sheets)

| Planilla | ID | Qué se usa |
| --- | --- | --- |
| Happy Food - Pedidos (dueño: jorgeduardo07@gmail.com) | `1Sr_ep7G2cpRSeH3YNMm0lzaFlHGuMk8Mio6qHb3Le_Q` | ORDENES (N°, Fecha, Cliente, Tipo, Estado) · DETALLE (N° OP, Código, Cant. Solicitada) · PRODUCTOS (CODIGO, PRODUCTO, ESTADO, UNIDAD, VU días, POLÍTICA) |
| Control de stock-KG (actualizada a diario; encabezado en fila 3) | `1Kv0DQjxqwH2zkEiKg1Izp1t-Jl2zuac2xi4ExRKcmQY` | STOCK CD / STOCK PLANTA / STOCK TRANSITO: CODIGO, Total (bultos por lote), Fecha limite de Entrega (excluye vencidos) |
| Happy Food - PRODUCCIÓN (solo análisis; el tablero NO la lee) | `1CZEC7YuURKd6JJKRHyXquVYY-ETB_DOEUT148EqawGA` | Hoja "Producción": Fecha Producción, COD, Cantidad de Bultos (desde jul-2024; oct24–feb25 posiblemente incompletos) |

**Trampas conocidas:**
- El Sheet "Happy Food - Stock" viejo (`1zAilIUUZq-KzrdCxkWaR6JXWHb4y8yVjQ8OMtOiupsI`) está congelado desde ago-2026: NO usar.
- Existe una planilla casi homónima "Control de stock.KG" (con punto, `1F1gwIzbFFqkB7AJZ3XQsYKnaCzGvg-5fBpHaF4YCNOI`) que NO es la fuente.
- Al leer pedidos por conector de Drive: usar descarga/export xlsx; la lectura como texto TRUNCA el archivo.
- Hay exportaciones cargadas como pedido común (ej.: OP 2028 "CENCOSUD RETAIL S.A." con tipo vacío, OP 2031 "COMERCIAL RAKKO SPA" como DISTRI) que se cuelan en la demanda doméstica si solo se filtra por tipo EXPO. Detectarlas por cliente.

## Metodología (la que corre en el tablero v2)

1. **Demanda** = Cantidad Solicitada; excluye EXPO, FASON, reclamos y cliente "RECLAMO". Semanas de lunes a domingo; historia desde dic-2025. Demanda semanal por SKU = 50% promedio histórico (desde su primera semana activa) + 50% promedio últimas 12 semanas.
2. **Universo**: códigos ≥3000, estado VIGENTE, unidad Bulto/Caja (~51 SKUs). Armados a pedido x24/x36 no se producen: su demanda va al SKU base a razón de unidades÷144 (mapa: 3002/3006→3000, 3012/3016→3010, 3022/3026→3020, 3036→3030, 3042/3046→3040, 3052/3056→3050, 3072/3076→3070, 3082/3086→3080, 3092/3096→3090, 3102/3106→3100, 3116→3110). SUPER x30 bandejas: 3001, 3011, 3021, 3041, 3051, 3101.
3. **Semielaborado 2xxx** ("de a mil": 2001→3001): bandejas ÷ unidades del bulto destino = bultos equivalentes, que suman al stock útil del 3xxx.
4. **Política mínima** = demanda×2 semanas + 1,6449×desvío muestral (95% de servicio), con tope demanda×(VU/7)×40%. **Contingencia** = percentil 95 semanal (interpolación lineal), mismo tope.
5. **Stock útil** = CD + Planta + Tránsito − lotes con Fecha límite de Entrega vencida + semielaborado convertido. **Disponible** = útil − comprometidos (órdenes estado PENDIENTE ≤60 días; parciales no cuentan; solo las líneas tildadas en el tablero).
6. **Producir** = máx(0; política mínima − disponible), redondeado hacia arriba. Estados: CRÍTICO (disponible < venta esperada de 7 días) / INSUFICIENTE (< contingencia) / AJUSTADO (< política) / SUFICIENTE (≤1,5× política) / EXCEDENTE.
7. **Venta esperada de 7 días**: modelo por cliente — tasa de pedidos semanal × cantidad típica por SKU, sumado sobre clientes activos (no es el promedio histórico del SKU).
8. **Clientes**: P(pedido próx. semana) = 1−e^(−tasa); INACTIVO si pasó más de máx(6 semanas, 3×cadencia mediana) sin pedir; POR PEDIR si pasó su cadencia; 🌱 NUEVO si tiene <12 semanas de historia (probabilidad tentativa; su demanda esperada sí cuenta).
9. **ABC**: Pareto por bultos históricos — acumulado ≤80% = A, ≤95% = B, resto C. No pondera margen ni kg.
10. **Kg por bulto**: parseados de la descripción del producto (3153/3173 = 1,4 kg confirmado); coinciden con el maestro de kg del archivo de stock.

## Datos del negocio (cortes recientes)

- Demanda doméstica ~2.300–2.800 kg/semana (~10–12 t/mes). Capacidad: media 12 meses 11,3 t/mes; máximo 14,8 t. Calendario laboral: L-V completo + sábado medio día = 5,5 días hábiles equivalentes/semana (~475 kg/día eq promedio, ~620 al ritmo del mejor mes).
- Sep-oct 2026: quiebre de stock fuerte (stock útil llegó a ~3,3 t de terminado); plan de recuperación en el doc del plan. Exportaciones puntuales: Cencosud Retail 4.846 kg + Rakko 2.066 kg.
- ~11 SKUs clase A concentran ~80% del volumen; los más grandes: 3113, 3121, 3131, 3093, 3073, 3083, 3141.

## Historia y lecciones

- El tablero original (ago-2026) leía los Sheets en vivo y funcionaba. En oct-2026 una versión hecha fuera de estos chats lo reemplazó por fotos comprimidas (gzip+base64 en 8 archivos .b64 en Drive) que acumuló 3 fallas en 3 semanas y lo dejó caído; se reconstruyó como v2 con lectura directa. No reintroducir snapshots en Drive sin razón fuerte y escritura atómica.
- Los caracteres invisibles (NBSP) en código se degradan al copiar y pegar en el editor de Apps Script: usar siempre escapes ` ` en texto ASCII.
- `google.script.run` puede dar HTTP 503 con varias cuentas de Google logueadas en el mismo navegador: usar un solo login o perfiles separados; `?debug=1` prueba el servidor sin pasar por ese canal.
- Pegar código nuevo en Apps Script NO actualiza la web app: hace falta Implementar → Administrar implementaciones → Nueva versión (la URL se mantiene).
- La URL para compartir es la forma `/macros/s/.../exec` SIN `/u/1/` (ese segmento es el índice de cuenta del que la copió y rompe el link para otros).
