# Happy Food | Traspaso técnico del proyecto Tecno → Supabase → IA

**Fecha de corte:** 22/10/2026.  
**Objetivo de este documento:** permitir que Claude continúe un proyecto más amplio de datos, automatización y analítica de Happy Food sin reconstruir el trabajo anterior.  
**Alcance:** reconstrucción estructurada de esta conversación y revisión de los archivos fuente disponibles. **No es una transcripción literal íntegra del chat.** Para obtener los mensajes literales, utilizar la exportación de datos de ChatGPT o copiar el historial desde la interfaz.

## 1. Resumen ejecutivo

Se implementó un flujo de sincronización desde **Tecno**, un sistema legado de Visual FoxPro con archivos DBF, en el servidor Windows **SRV-HAPPY** (Windows Server 2008 R2), hacia **Supabase/PostgreSQL**. El destino mantiene dos tablas en el esquema `tekno`: encabezados de ventas y detalles. Se completó una carga inicial, se probó una actualización incremental, y se instaló una tarea programada cada **10 minutos**.

**Estado efectivamente demostrado al cierre:**
- Supabase contiene **6.060 ventas**, con **5.929 activas y 131 eliminadas**, y **39.982 detalles**, con **29.500 activos y 10.482 eliminados** (resultado SQL del 22/10/2026).
- Los datos proceden de la extracción del 22/10/2026. Se verificaron cantidades, IDs y estados; **no** hubo una auditoría exhaustiva campo a campo de los 46.042 registros.
- Se confirmó un ciclo completo de VSS → copia → CSV → comparación → limpieza de VSS sin cambios, así como una ejecución real manual de **73 registros incrementales**.
- Existe la tarea de Windows `HappyFood_Tekno_Supabase_10min`, **habilitada**, ejecutando `HappyAuto.exe sincronizar` cada 10 minutos bajo `SRV-HAPPY\Administrador`. Se observó una ejecución automática a las **11:47** con resultado **0** y carpetas posteriores a las **11:57** y **12:07**.
- El resumen de la ejecución del **22/10 a las 12:07** muestra **cero cambios**, con hashes de los CSV iguales a la referencia confirmada. **Aún no se observó una nueva venta transmitida por la tarea programada de manera completamente desatendida**. Por ello, la automatización está instalada y funciona en escenarios sin novedades, pero la escritura desatendida con cambios reales sigue pendiente de validación final.

## 2. Contexto y arquitectura

**Origen**
- Servidor: `SRV-HAPPY`, Windows Server 2008 R2 (Windows 6.1.7601), .NET Framework 4.8 / compilador `csc.exe` disponible.
- Unidad de Tecno: `F:`.
- Ruta habitual de archivos: `F:\TEKNO\ssoft.hap\DATOS\`.
- DBF: `movivent.DBF` (encabezados de ventas), `DETAVENT.DBF` (líneas/detalles).
- Los DBF pueden estar abiertos por Tecno. Se utiliza **DiskShadow/VSS** para obtener una instantánea consistente sin copiar desde archivos activos y sin modificar los datos fuente.
- Extracción DBF a CSV mediante `Extractor.exe`, en `C:\HAPPY_EXTRACTOR\happy_extractor_v1\Extractor.exe`. Conserva `registro_origen` (posición/identificador DBF), `eliminado_origen` y todos los campos DBF como texto, con espacios significativos.
- Algunos campos DBF MEMO u otros tipos no se interpretan por completo: el extractor advierte que los exporta como texto decodificado. Esta limitación debe considerarse antes de modelar datos.

**Destino**
- Supabase: proyecto `happyfood-tekno`; project ref: `igcewbadhejtesbogewm`.
- Esquema PostgreSQL: `tekno`.
- Tablas `tekno.ventas` y `tekno.ventas_detalle`.
- Estructura relevante: `id` identidad, `registro_origen` INTEGER UNIQUE, `datos` JSONB, `eliminado_origen` BOOLEAN, `fecha_sincronizacion` TIMESTAMPTZ.
- Se utiliza una función PL/pgSQL `tekno.sincronizar_lote(text,jsonb)`, con upsert (`ON CONFLICT (registro_origen)`) y comparación para evitar actualizaciones cuando los datos ya coinciden.
- Endpoint Edge Function: `https://igcewbadhejtesbogewm.supabase.co/functions/v1/happyfood-sync`.
- Autenticación Edge con `withSupabase({auth:"secret:happyfood_sync_server"})` y clave secreta nombrada. La conexión de la Edge Function a PostgreSQL usa la variable del entorno `SUPABASE_DB_URL` y `postgres` npm. **Nunca copiar secretos de producción a Claude ni a documentación.**
- Acción para escritura: `sincronizar_lote` con `tabla`, `registros` y `confirmar_escritura:"ESCRIBIR_LOTE"`.
- Payload típico: `{ "accion":"sincronizar_lote", "tabla":"ventas", "registros":[{"registro_origen":6061,"datos":{...},"eliminado_origen":false}],"confirmar_escritura":"ESCRIBIR_LOTE" }`.
- La Edge Function limita solicitudes a **1–100 registros** y responde tanto estado HTTP como resultado SQL (`ok`, `procesados`).

## 3. Cronología de la implementación

**20/10: extracción inicial**
- Instantánea VSS con DiskShadow y copia DBF a carpetas locales.
- `movivent.csv`: 6.053 registros (5.922 activos, 131 eliminados).
- `DETAVENT.csv`: 39.929 registros (29.453 activos, 10.476 eliminados).
- Resguardados los CSV de referencia en `C:\HAPPY_EXTRACTOR\CSV_20261020`.
- Pruebas de autenticación HTTPS, validación de lotes y conexión PostgreSQL.

**21/10: primera escritura y carga completa**
- Prueba controlada en ventas `registro_origen=6045` (orden 15149) y respaldo `tekno.backup_sync_6045`.
- Un primer HTTP 500 produjo `PostgresError: Lote invalido`; se resolvió la serialización del parámetro JSONB en Edge pasando `${sql.json(registros)}` en lugar de `${JSON.stringify(registros)}::jsonb`.
- Primera escritura controlada devolvió HTTP 200 y `procesados=1`; la fila era igual a la ya almacenada, no necesariamente cambió su marca temporal.
- Se armaron 461 lotes: 61 de ventas, 400 de detalle.
- Se respaldó `tekno.ventas` y `tekno.ventas_detalle` en tablas `tekno.backup_ventas_20261021` y `tekno.backup_ventas_detalle_20261021`.
- Se procesaron todos los lotes y se verificaron en SQL las cantidades y los estados iniciales: 6.053 y 39.929.

**22/10: segunda extracción y prueba incremental**
- Se creó nueva instantánea VSS y se generaron `C:\HAPPY_EXTRACTOR\CSV_20261022\movivent.csv` y `...\DETAVENT.csv`.
- Se confirmó que `Extractor.exe` está bajo `happy_extractor_v1` (no en la raíz de `C:\HAPPY_EXTRACTOR`).
- El comparador requería `C:\HAPPY_EXTRACTOR\CSV_NUEVO`; se creó una unión NTFS/junction hacia `CSV_20261022` mediante `mklink /J`.
- Detección: **ventas 7 nuevas + 3 modificadas**; **detalles 53 nuevos + 10 modificados**; ningún `registro_origen` faltante.
- Se revisó identidad de los 13 registros existentes: ventas 6017, 6031, 6034 y detalle 39732–39734, 39736–39742. Comparación SQL coincidió en **3/3 y 10/10** para campos comerciales claves.
- Respaldo previo incremental en `tekno.backup_ventas_pre_incremental_20261022` y `tekno.backup_detalle_pre_incremental_20261022`.
- Envío manual supervisado de dos archivos: `ventas_cambio_0001.json` con 10 ventas y `ventas_detalle_cambio_0001.json` con 63 detalles (incluye 6 marcados eliminados); HTTP 200 para ambos.
- Totales finales confirmados en Supabase: **ventas 6060 = 5929 activas + 131 eliminadas**; **detalle 39982 = 29500 activos + 10482 eliminados**.
- Se eliminó la instantánea de VSS desde `diskshadow` por ID. Atención: `vssadmin delete shadows` no pudo borrarla por haber sido creada con DiskShadow; `diskshadow > delete shadows id {GUID}` sí funcionó. Se confirmó `vssadmin list shadows` sin instantáneas.

**22/10: programa automático**
- El usuario entregó fuentes `HappyControlIncremental.cs`, `HappyEnviarLote.cs`, `HappyEnviarSerie.cs`, `CREAR_VSS.txt` en `Archivo.zip`.
- Se construyó `HappyAuto.cs` y los BAT asociados, instalados en `C:\HAPPY_EXTRACTOR\SYNC`.
- Primera versión generó errores de compilación `CS1010` por cadenas mal construidas; se corrigieron.
- Primera prueba falló porque `vssadmin list shadows` devolvía código de salida 1 al no haber instantáneas; se corrigió el manejo de ese caso para Windows Server 2008 R2.
- Posterior prueba completa **sin envío**: creación y limpieza VSS, copia DBF, extractor, comparador, `lotes=0`, resultado `PRUEBA CORRECTA`.
- Se inicializó referencia confirmada a partir de los CSV del 22/10. Se habilitó autorización local de escritura y se probó `HappyAuto.exe sincronizar`; resultó `SIN CAMBIOS. BASE AVANZADA.`
- Tarea creada desde BAT instalador: `HappyFood_Tekno_Supabase_10min`, bajo `SRV-HAPPY\Administrador`, con contraseña provista localmente, repetición cada 10 min, segundo plano.
- `schtasks /query /tn "HappyFood_Tekno_Supabase_10min" /v /fo LIST` verificó: habilitada, último resultado 0, última ejecución 11:47, próxima 11:57, y repetición cada 10 minutos.
- Registro de ejecución 12:07 `C:\HAPPY_EXTRACTOR\SYNC\AUTO_ESTADO\EJECUCIONES\20261022_120700_317\CAMBIOS\RESUMEN_CAMBIOS.txt`: 6060 ventas, 39982 detalles, sin registros nuevos/modificados/faltantes, hashes iguales.

## 4. Rutas e inventario de programas

- Código/programas de sincronización: `C:\HAPPY_EXTRACTOR\SYNC\`.
- Ejecuciones automáticas: `C:\HAPPY_EXTRACTOR\SYNC\AUTO_ESTADO\EJECUCIONES\<timestamp>`.
- Base incremental confirmada: `C:\HAPPY_EXTRACTOR\SYNC\AUTO_ESTADO\BASE_CONFIRMADA`.
- Archivo que bloquea nuevas escrituras en fallo: `C:\HAPPY_EXTRACTOR\SYNC\AUTO_ESTADO\REQUIERE_REVISION.txt`.
- Archivo de exclusión mutua durante la ejecución: `C:\HAPPY_EXTRACTOR\SYNC\AUTO_ESTADO\en_ejecucion.lock`.
- Datos de credenciales: cifrados por DPAPI del usuario Windows, almacenados en la carpeta de aplicación local de la cuenta; **no transportar el archivo DPAPI como documentación**.
- DBF extracción 22/10: `C:\HAPPY_EXTRACTOR\COPIA_20261022`.
- CSV 20/10: `C:\HAPPY_EXTRACTOR\CSV_20261020`.
- CSV 22/10: `C:\HAPPY_EXTRACTOR\CSV_20261022`.
- Comparación manual: `C:\HAPPY_EXTRACTOR\SYNC\CAMBIOS_PRUEBA_01`.
- Source main: `HappyAuto.cs` (consultar versión del paquete `HappyFood_Auto_10min_Piloto_V1_FIX_VSS.zip`).
- Otros fuentes: `HappyControlIncremental.cs`, `HappyEnviarLote.cs`, `HappyEnviarSerie.cs`.
- BAT automáticos: `01_COMPILAR_AUTO.bat`, `02_PREPARAR_BASE_CONFIRMADA.bat`, `03_PROBAR_CICLO_COMPLETO_SIN_ENVIO.bat`, `04_VER_ESTADO.bat`, `NO_EJECUTAR_AUN_05_AUTORIZAR_ESCRITURA.bat`, `NO_EJECUTAR_AUN_06_PRUEBA_REAL.bat`, `NO_EJECUTAR_AUN_07_INSTALAR_TAREA.bat`.

## 5. Operación y comprobaciones

**Consultar tarea instalada:**
```bat
schtasks /query /tn "HappyFood_Tekno_Supabase_10min" /v /fo LIST
```

**Deshabilitar ante un incidente (sin borrar la tarea):**
```bat
schtasks /change /tn "HappyFood_Tekno_Supabase_10min" /disable
```

**Volver a habilitar solo después de diagnóstico:**
```bat
schtasks /change /tn "HappyFood_Tekno_Supabase_10min" /enable
```

**Consultar totales en Supabase:**
```sql
SELECT 'ventas' AS tabla, COUNT(*) AS total,
       COUNT(*) FILTER (WHERE NOT eliminado_origen) AS activos,
       COUNT(*) FILTER (WHERE eliminado_origen) AS eliminados,
       MAX(registro_origen) AS ultimo_id,
       MAX(fecha_sincronizacion) AS ultima_sincronizacion
FROM tekno.ventas
UNION ALL
SELECT 'ventas_detalle', COUNT(*),
       COUNT(*) FILTER (WHERE NOT eliminado_origen),
       COUNT(*) FILTER (WHERE eliminado_origen),
       MAX(registro_origen), MAX(fecha_sincronizacion)
FROM tekno.ventas_detalle;
```

**Revisar logs:** en la última carpeta de `AUTO_ESTADO\EJECUCIONES` consultar `ejecucion.log`; el archivo `RESUMEN_CAMBIOS.txt` está habitualmente dentro de **`CAMBIOS\`**, no directamente en la raíz de la ejecución.

**Precauciones:** no volver a ejecutar `02_PREPARAR_BASE_CONFIRMADA.bat` en producción sin comprobar si Supabase recibió todos los cambios; no borrar `REQUIERE_REVISION.txt` sin conciliación; no ejecutar los BAT históricos de carga inicial; no reutilizar credenciales DPAPI bajo otra cuenta; no publicar claves `sb_secret_*`, contraseñas Windows ni `SUPABASE_DB_URL`.

## 6. Diseño y riesgos técnicos pendientes

1. **Comprobar al menos una escritura programada con novedades reales.** Las ejecuciones programadas observadas tenían cambios cero; un resultado `0` de Task Scheduler solo confirma que el proceso finalizó, no que haya replicado una venta reciente.
2. **Habilitar monitoreo y alertas.** Alertar si no hay ejecución exitosa en ~20–30 minutos, si aparece `REQUIERE_REVISION.txt`, si una copia VSS no se elimina o si una tarea retorna no cero.
3. **Validar exactitud de datos extremo a extremo.** Las verificaciones SQL documentadas comprobaron cantidades, IDs y marcadores de eliminación, no todas las claves/valores JSONB. Diseñar una auditoría por hash canónico por registro y muestreo comercial.
4. **No confundir `registro_origen` con una clave comercial permanente.** Es un identificador posicional del DBF; operaciones de `PACK`/reestructuración pueden provocar reutilización de posiciones. El sistema actual compara claves comerciales (`ORDEVENT/CODICOMP/NUMEVENT` para ventas, `ORDEFINA/ORDECOMP` para detalles) y bloquea si faltan IDs, pero no garantiza detectar todos los casos tras PACK.
5. **Seguridad transaccional:** el `HappyAuto` de piloto bloquea ante un fallo de red o respuesta incierta y requiere conciliación manual. Una llamada SQL podría haberse confirmado aunque falle el HTTP; no borrar el bloqueo ni reenviar a ciegas.
6. **Línea base y atomicidad:** el programa debe avanzar la referencia solo después de confirmar todos los lotes. Verificar su comportamiento ante corte eléctrico, error VSS, reinicio del servidor y fallos parciales entre tabla de ventas y detalles.
7. **No se ha probado un volumen grande de cambios en modo desatendido**, ni alertas por credenciales expiradas, ni rotación/retención de logs.
8. **Copias y capacidad Supabase:** se crearon varias tablas `backup_*` dentro de la misma base. Estas copias no sustituyen un respaldo externo y consumen espacio en el plan Free. Revisar capacidad, retención, costes y política de recuperación antes de un despliegue productivo crítico.
9. **Seguridad y privacidad:** evaluar controles de acceso por rol, rotación de secretos, RLS, auditoría, cifrado, y evitar subir datos comerciales innecesarios a servicios de IA.
10. **El código piloto no debe tratarse como solución definitivamente certificada de producción** sin pruebas de nuevos registros automáticos y recuperación ante fallas.

## 7. Próximos objetivos para el proyecto mayor con Claude

### Prioridad 1 — Cerrar sincronización operativa
- Observar una nueva venta real en Tecno y confirmar que llega por la tarea automática dentro de los 10 minutos siguientes (con tolerancia a duración de ejecución).
- Guardar prueba de ejecución (`ejecucion.log`, `RESUMEN_CAMBIOS.txt`) y los registros de Supabase.
- Diseñar tablero de estado (último inicio, último éxito, filas enviadas, latencia, errores, VSS, alertas).
- Revisar las protecciones de PACK y esquema DBF.

### Prioridad 2 — Base de datos de reporting
- Diseñar capa tipada de datos encima de JSONB (`ventas`, líneas, clientes, artículos, vendedores, listas, impuestos) y sus relaciones; normalizar cadenas numéricas con espacios y fechas.
- Documentar significado de `CODICOMP`, `TIPOVENT`, `ORDEVENT`, `ORDECOMP`, signos negativos en `NETOFINA` y registros eliminados.
- Evitar doble conteo y definir convenciones para notas de crédito, devoluciones y documentos asociados.
- Construir tests de conciliación Tecno vs Supabase, por día/mes/comprobante.

### Prioridad 3 — Inteligencia comercial Happy Food
- KPIs: venta neta/bruta, mix, unidades por SKU, cliente, canal, región, vendedor, evolución temporal y margen si hay datos de costo.
- Relevamiento de tablas adicionales de Tecno: maestros de artículos, clientes, inventario, compras, saldos, precios y descuentos.
- Reportes de sell-in/sell-out, efectividad promocional e inversión por supermercados.
- Capa de consultas en lenguaje natural con IA, acceso seguro y trazabilidad de fuentes.

## 8. Recomendación para entregar contexto a Claude

Cargar en el proyecto de Claude este documento Markdown como **contexto principal**, junto con los cuatro fuentes de `Archivo.zip` y la **versión definitiva corregida** de `HappyAuto.cs`/BAT dentro del paquete de piloto. Adjuntar CSV/DBF/JSON comerciales solo si son estrictamente necesarios y con políticas de datos correspondientes. Evitar incluir archivos de credenciales o parámetros secretos.

**Solicitud inicial sugerida para Claude:**
> Estoy construyendo el proyecto integral de datos, automatización e IA de Happy Food. Tomá este documento como historial técnico de lo ya realizado. No reconstruyas desde cero ni des por comprobado lo que todavía no se validó. Primero auditá el sincronizador automático Tecno → Supabase del Windows Server 2008 R2, verificá el caso de nuevas ventas realmente replicadas por la tarea de 10 minutos, evaluá fallos/recuperación y monitoreo. Luego ayudame a diseñar el modelo analítico y los tableros comerciales sobre Supabase. Proponé pasos concretos, seguros y compatibles con el entorno legado.

---
**Nota de integridad:** este documento consolida resultados observados en el chat y código de los ZIP disponibles. No prueba por sí solo el funcionamiento futuro de la tarea ni constituye una copia literal de todos los mensajes.
