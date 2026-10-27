# Happy Food — Tablero de producción v2 (oct-2026) — proyecto NUEVO

## Qué es

El tablero reconstruido de cero sobre el motor que funcionaba, con tres diferencias clave frente a la versión que se rompió:

1. **Lee los Sheets EN VIVO**, sin fotos comprimidas ni respaldos en Drive (eso fue lo que falló: rotaciones a medias y GZIP corrupto). Cada carga trae los datos del momento.
2. **El stock sale de "Control de stock-KG"** — el archivo que el equipo actualiza — y no del Sheet "Happy Food - Stock" viejo, congelado desde agosto. El lector encuentra solo el encabezado aunque esté en la fila 3.
3. **Incluye los tildes de pendientes**: en la pestaña "Pendientes ✓" destildás los pedidos que no vas a producir y el plan se recalcula al instante; "Guardar selección" lo deja fijo para todos.

También trae: ?debug=1 en la URL para diagnóstico, testGetData/testHojas para probar desde el editor sin implementar, mensajes de error que dicen qué hoja falta, y cero caracteres invisibles (seguro de copiar y pegar).

## Instalación (proyecto nuevo)

1. script.google.com con **leandrogiomprini@gmail.com** (tiene acceso a los tres archivos, verificado hoy) → **+ Nuevo proyecto** → nombre: "Happy Food Tablero v2".
2. Pegar `Code.gs` en `Código.gs` (borrar lo que trae).
3. **+ → HTML** → nombre exacto: **Index** → pegar `Index.html`.
4. Guardar. Probar sin implementar: elegir **testGetData** en el desplegable de arriba → Ejecutar → autorizar → el Registro debe decir "OK en ... ms, plan: 51 SKUs...".
5. Implementar → Nueva implementación → **Aplicación web** → Ejecutar como: **Yo** → Quién accede: elegir (si son solo cuentas conocidas, cargar `ALLOWED_EMAILS` en CONFIG) → Implementar.
6. Copiar la URL `/exec` (sin `/u/1/`) y repartirla. El tablero viejo se puede archivar: Implementar → Administrar implementaciones → anular la implementación vieja para que nadie siga entrando a la URL rota.

## Actualizaciones futuras

Pegar código nuevo NO actualiza la web: Implementar → Administrar implementaciones → ✏️ → **Nueva versión** → Implementar (la URL se mantiene).

## Si algo falla

- `URL/exec?debug=1` → estado real del servidor en texto plano.
- En el editor: `testHojas` lista las hojas reales de ambos Sheets; los nombres esperados son ORDENES / DETALLE / PRODUCTOS (pedidos) y STOCK CD / STOCK PLANTA / STOCK TRANSITO (Control de stock-KG).
- Si el equipo renombra o reemplaza "Control de stock-KG", actualizar `STOCK_ID` en CONFIG (es la parte larga de la URL del archivo).
