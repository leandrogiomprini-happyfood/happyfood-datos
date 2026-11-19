# HappyFood · Traspaso del macroproyecto de datos (19/11/2026)

Para arrancar el **módulo económico-financiero** en un chat nuevo sin perder lo hecho. Resume el estado
de la base, las reglas acordadas con Cuci y lo pendiente. El detalle de cada cambio está en el
encabezado de cada migración (`supabase/migrations/001` a `059`).

Cómo trabaja Cuci (aplicar siempre): no es técnico; todo paso a paso. No quiere escribir scripts. Cada
cambio a la base es un archivo `.sql` numerado que él pega en Supabase → SQL Editor → Run, con una
consulta de control al final. Los archivos se le dejan en su Mac en `~/Downloads/HappyFood_Hojas`.
No se pisan archivos ya entregados: cambio nuevo = migración nueva. Prefiere lo más automático.
Nunca copiar claves (sb_secret, contraseñas, JSON de la cuenta de servicio, URL de la base) al chat,
documentos o repositorio. Tekno y sus DBF no se modifican nunca.

## 1. Infraestructura

| Pieza | Qué es |
|---|---|
| Supabase | Proyecto `happyfood-tekno` (ref `igcewbadhejtesbogewm`), plan Free. Esquemas: `tekno` (copia cruda), `hojas` (planillas), `core` (vistas tipadas), `calc` (cálculos), `rpt` (resultados guardados), `public.reporte_*` (lo único que ve Looker) |
| Sync Tekno | En el servidor SRV-HAPPY: `HappyAuto.exe` (ventas, cada 10 min) y `HappyTablas.exe` (maestros, cobranzas, compras, pagos). Ver `docs/traspaso_tekno_supabase.md` y `sync-tekno/tablas/tablas_tekno.txt` |
| Sync planillas | Edge Function `happyfood-sync-hojas` con cuenta de servicio de Google `supabase-lector` (solo lectura; cada planilla se comparte como Lector). Lee Google Sheets y .xlsx en Drive. `hojas.fuentes` lista cada pestaña y cada cuánto se lee |
| Recálculos (pg_cron) | `refrescar_rpt` cada 10 min (ventas, cobranzas); `refrescar_insumos` a los :10 y :40; `refrescar_pedidos` cada 10 min; `leer_hojas` cada 5 min (máx. 4 pestañas por vez); `control_hojas` a los :20 y :50 |
| Looker Studio | Conexión PostgreSQL con usuario `looker_lectura` (SSL destildado; solo ve `public`). Usuarios aparte por vendedor: `looker_pablo`, `looker_esteban` |
| Repositorio | `leandrogiomprini-happyfood/happyfood-datos` |
| Plan | Doc "HappyFood — Macroproyecto de datos y sistemas" en Claude (claude.ai/artifact/CFNrBq8ZNTThMv6JdSuACR) |

## 2. Qué hay en la base hoy

| Área | Fuente | Vistas para Looker | Notas |
|---|---|---|---|
| Ventas | Tekno (movivent/detavent) | `reporte_ventas` | Neto sin IVA; presupuestos: neto = total. Kg y costo por producto; contribución marginal |
| Costos de producto | Planilla movivent, hoja kgxArtiActual (costo por kg por mes) | dentro de ventas y producción | Costo del mes; si falta, el último anterior |
| Cobranzas | Tekno (movicobr, detacobr, auxiapli) | `reporte_cobranzas_neto` | Neto sin IVA prorrateado por comprobante cancelado; a cuenta con el ratio neto/total del cliente |
| Deuda de clientes | Tekno | dentro de los informes de vendedores | |
| Compras y pagos | Tekno (movicomp, detacomp, venccomp, movipago, detapago, aplicomp, maesprov, tablrubr, maescuen) | **solo vistas core**, sin reporte todavía: `core.compras`, `compras_detalle`, `compras_vencimientos`, `pagos`, `pagos_medios`, `pagos_aplicaciones`, `proveedores`, `rubros`, `plan_cuentas` | **Base del módulo económico-financiero**: falta validar contra Tekno y clasificar rubros |
| Insumos | Compras R-COM02, conteos, recetas, plan semanal | `reporte_stock_insumos`, `reporte_insumos_pedir`, `reporte_oc_pendientes`, `reporte_faltantes_plan`, `reporte_estado_insumos` | Previsión día por día con el plan |
| Producción | Parte de producción (Forms), masas, plan semanal | `reporte_produccion`, `reporte_plan_vs_real`, `reporte_plan_vs_real_dia`, `reporte_masas`, `reporte_produccion_dia`, `reporte_produccion_costo` | Kg = bultos × kg por bulto del maestro |
| Stock de PT | "Happy Food - Stock" (STOCK_CD, STOCK_Planta) | `reporte_stock_pt`, `reporte_stock_hf` | "Control de stock-KG" ya no se lee (era copia) |
| Ajustes de stock | "Happy Food - Ajuste Stock" (DETALLE) | `reporte_ajustes_stock` | Kg y valor al costo; agrupado por motivo |
| Pedidos pendientes | Planilla de Pedidos (ORDENES, DETALLE) | `reporte_pedidos_pendientes`, `reporte_pedidos_pendientes_cliente` | Monto estimado sin IVA: último precio del cliente → promedio 60 d → 12 meses |
| Personal | Maestro (Personal_maestro_v2.xlsx) + reloj facial (Asistencia Anual.xlsx, export manual como nueva versión) | `reporte_asistencia`, `reporte_ausencias`, `reporte_dotacion_dia` | Horas con descanso incluido (provisorio) |
| Vendedores | Carteras en `core.cartera_manual` + vendedor Tekno | `pablo_*`, `esteban_*` | Sin costos |

## 3. Reglas acordadas (no volver a discutir)

- Todo en **neto sin IVA**. Presupuestos (P2/Q2): el neto es el total. Valor Declarado de pedidos no se usa.
- Clientes internos (no son venta): 00405 y similares de mismo CUIT; **LAPDI 00407 = donaciones**. Banco de Alimentos, consumo interno, reclamos y muestras: no se facturan.
- Envases unitarios 1000–2000 facturados a $0,01 = reposiciones por reclamo, no ventas.
- Producción: Super, Distri y Semielaborado suman kg; **Rearmado y Retrabajo no** (cambio de formato). Semielaborado en bandejas → bulto 3xx1 (÷30).
- Kg por bulto: maestro `core.productos`. Correcciones: 3153/3173 = 20 × 70 g; 9001 soja = 45 g; **3161 Talita Andina = 24 × 100 g** (2,4 kg).
- Sábados 4 h, resto 8 h. Personal "A demanda" (centro de distribución) no genera ausencias, suma en dotación.
- Insumos: 16 → reemplazado por 17 (borrar el reemplazo a fin de diciembre: tarea programada el 24/12/2026).

## 4. Pendiente

**Datos a confirmar por Cuci**
- Peso real de Marinera Andina y Clásica: maestro 70 g (1,4 kg/bulto) contra el plan, que usa 1,7 kg/bulto.
- "Envasar": ¿es Semielaborado o Rearmado? (para nombrar columnas).
- Jose Daniel Cortez: depósito pero "cuenta para producción = Sí".
- Horas trabajadas con o sin descanso.
- Pedidos "Parcial": hoy fuera de pendientes (se asume que lo no entregado no se manda).
- Precio de distribuidores nuevos: hoy promedio general; propuesto promedio por tipo de cliente.
- Política de stock 2 semanas: criterio propuesto (12 semanas de venta); exportación aparte.
- 1 producto en stock sin kg en el maestro (identificar con la consulta de la 051).

**Correcciones en planillas (las hace el equipo)**
- Plan semanal: QUESO cargado con código 3121 (va 3141); kilos que no cierran con bultos.
- Parte de producción: el "Lugar" sale siempre "Planta".
- 9001 descripción en Tekno (X45GR); 3161 descripción en Tekno (dice P90GR).
- Hoja KG: bandeja 17; columna AK de 16/224/225; Compras 184 y 125/126.

**Clientes sin código Tekno todavía**: Enrique Reyes (Ferniplast), CYRE (Cordiez), Farmar, Promacron,
Gazzoni, Tristan Segovia. Se emparejan solos al darse de alta.

**Calidad / HACCP** (plan, sección Aplicaciones): validar límites de PCC; higrómetros H01/H02 con
calibración vencida desde 02/2026; confirmar registro de gluten en planta; diseño de pantallas PCC
en borrador (artifact "App de planta · Controles PCC").

**Infraestructura**: decidir Supabase Pro (backups), backup humano y volver a activar SSL.

## 5. Módulo económico-financiero: punto de partida

Objetivo de Cuci: saber dónde está parada la empresa, lo que viene y tener sensibilidad de la situación.

| Pregunta | Dato | Dónde está | Estado en la base |
|---|---|---|---|
| ¿Ganamos plata? (resultado mensual) | Ventas netas, costo de lo vendido | Tekno + costos | ✔ |
| | Gastos (sueldos, servicios, impuestos, fletes, comisiones…) | **Tekno: facturas de compra y gastos con rubro** | En `core.compras`/`compras_detalle`; falta validar y clasificar rubros |
| | Gastos fuera de Tekno | Planilla de gastos | Falta conectar |
| ¿Cuánta caja tenemos y vamos a tener? | Cobranzas pasadas y a cobrar (vencimientos) | Tekno | ✔ (`core.ventas_vencimientos`, cobranzas) |
| | Pagos pasados y a pagar | Tekno (vencimientos de compra, pagos) | En core; falta reporte |
| | Saldos de bancos, cheques, financiación | **Planilla de situación financiera (monitor manual)** | Falta conectar; cheques (CHEQCOBR/CHEQPAGO) no se sincronizan aún |
| | Compras comprometidas | Planilla de compras (R-COM02) + OC pendientes | ✔ (OC de insumos) |
| ¿Qué viene? | Pedidos pendientes, plan de producción | Pedidos, plan | ✔ |

Primeros pasos sugeridos:
1. Pedir a Cuci la planilla de gastos y el monitor de situación financiera (link + compartir con la cuenta de servicio).
2. Validar `core.compras` contra Tekno (un mes: total por rubro) y armar la clasificación de rubros → líneas del estado de resultados.
3. Estado de resultados mensual (ventas − costo − gastos por línea) y flujo de fondos semanal proyectado (cobros por vencer + pedidos pendientes − pagos por vencer − sueldos).
4. Sumar cheques de Tekno si el monitor no los cubre.
