# Sistema de Stock de Insumos — Happy Food
## Documento de diseño · v2 · 20/08/2026

---

## 1. Decisiones tomadas

| Decisión | Elegido | Consecuencia |
|---|---|---|
| Cómo se determina el egreso | **Teórico por receta** | Cero carga extra en planta. Requiere conteo físico para reconciliar. |
| Alcance Fase 1 | **Todos los insumos (~100 activos de 340 en el maestro)** | El cuello de botella pasa a ser completar el BOM, no la tecnología. |
| Plataforma | **Google Sheets + Apps Script** | Se conecta con Compras, PRODUCCIÓN y el Planificador, que ya viven ahí. |
| Conteo físico | **Semanal, todos los ítems** | ~3-5 h/semana de una persona. Ver la advertencia en §6. |

**Decisión adicional, tomada durante el relevamiento:** el motor de consumo se alimenta del **parte diario de producto terminado**, no de la declaración de masas.

> Motivo: la declaración de masas (`Happy Food - PRODUCCIÓN`, pestaña de masas/premezclas) se dejó de cargar el **23/06/2026**. No hay un solo registro en dos meses. El parte de PT, en cambio, se sigue cargando todos los días (último: 19/08/2026, 55 partes en agosto). Construir sobre la declaración de masas era construir sobre un dato muerto.

---

## 2. Arquitectura

```
                 ┌──────────────────────────────┐
   YA EXISTE ──▶ │ Compras R-COM02              │──▶ maestro de insumos,
                 │  · maestro insumos (340)     │    proveedores, lead time real,
                 │  · proveedores (140)         │    e INGRESOS (recepciones de OC)
                 │  · OC detalle (2.070 líneas) │
                 └──────────────────────────────┘
                 ┌──────────────────────────────┐
   YA EXISTE ──▶ │ Happy Food - PRODUCCIÓN      │──▶ EGRESOS teóricos
                 │  · parte diario de PT (vivo) │    bultos → unidades → masas → kg
                 └──────────────────────────────┘
                 ┌──────────────────────────────┐
   YA EXISTE ──▶ │ BOM (Control Stock Insumos)  │──▶ recetas kg/masa y kg/unidad
                 │  · dic-2023, incompleto      │
                 └──────────────────────────────┘
                 ┌──────────────────────────────┐
   HAY QUE     ─▶│ CONTEO FÍSICO semanal        │──▶ saldo inicial + reconciliación
   CREAR         └──────────────────────────────┘
                 ┌──────────────────────────────┐
   YA EXISTE ──▶ │ Planificador de Producción   │──▶ PREVISIÓN de consumo
                 │  · bultos a producir por SKU │
                 └──────────────────────────────┘
                                 │
                                 ▼
                    STOCK ACTUAL · ALERTAS · PREVISIÓN
```

**Ecuación central:**

```
Stock(hoy) = Último conteo físico
           + Recepciones de OC desde ese conteo
           − Consumo teórico desde ese conteo
           ± Ajustes
```

El conteo semanal reinicia el saldo, así que el error teórico nunca acumula más de 7 días. Ese es el motivo de fondo por el que el conteo importa más que cualquier fórmula.

---

## 3. Cómo se calcula el consumo

```
bultos declarados en el parte
   × unidades por bulto            (hoja CONV_SKU)
   = unidades producidas
   ÷ unidades por masa             (rinde, hoja CONV_SKU)
   = masas equivalentes
   × kg de insumo por masa          (hoja BOM_MASA)
   = kg consumidos
```

Los rellenos, baños y flexibles no pasan por masa: se calculan directo por unidad producida (hoja `BOM_UNIDAD`).

### Regla anti doble conteo

Un alfajor pasa dos veces por el parte: primero como **semielaborado** (bandeja x3, código 2xxx) y después como **bulto super** (código 3xxx, armado desde esas bandejas). Contar la masa en ambas etapas la duplica.

Regla implementada: un SKU `3xxx` cuyo "padre" `2xxx` (mismo número, primer dígito 2) se produjo, **no** imputa masa; sólo imputa empaque. Los SKU que se envasan directo —Talitas, Marineras, galletas familiares de 120 g— sí imputan masa en el envasado.

SKU que hoy se arman desde semielaborado: `3000, 3001, 3021, 3040, 3070, 3090, 3101, 3110`.

---

## 4. Validación del BOM contra las compras reales

Contrastando el consumo teórico de 12 meses (ago-2025 a ago-2026) contra lo efectivamente recibido por OC en el mismo período:

| Insumo | Teórico 12m | Recibido 12m | Ratio | Lectura |
|---|---:|---:|---:|---|
| Dulce de Leche | 8.625 kg | 8.375 kg | **1,03** | La receta cierra |
| Fécula de Mandioca | 5.662 kg | 5.350 kg | **1,06** | Cierra |
| Goma Xántica | 452 kg | 452 kg | **1,00** | Cierra |
| Baño Chocolate Diet | 3.636 kg | 3.930 kg | **0,93** | Cierra |
| Aceite Alto Oleico | 11.270 kg | 13.139 kg | **0,86** | Cierra |
| Trigo Sarraceno | 4.818 kg | 5.925 kg | 0,81 | Cierra |
| Dulce de Leche Diet | 8.000 kg | 11.000 kg | 0,73 | Cierra |
| Harina de Arroz | 17.447 kg | 35.100 kg | 0,50 | Desalineado |
| Polidextrosa | 9.324 kg | 34.075 kg | 0,27 | Desalineado |
| Almidón de Maíz | 17.020 kg | 73.750 kg | 0,23 | Desalineado |
| Harina de Maíz | 15.649 kg | 69.250 kg | 0,23 | Desalineado |
| Baño Chocolate Reg | 8.092 kg | 5.000 kg | **1,62** | Receta sobreestima |

**Resultado:** 16 insumos coherentes, 19 desalineados por debajo, 5 por encima.

**Lectura, con niveles de confianza:**

- *[Seguro]* Las recetas de **rellenos y baños** son confiables. Que el dulce de leche dé 1,03 sobre 8,6 toneladas anuales valida toda la cadena de conversión: bultos → unidades → recetas. No es casualidad.
- *[Probable]* Las recetas de **premezcla están mal o incompletas**. El patrón (todas las harinas y almidones entre 0,23 y 0,50, todos en la misma dirección) apunta a una causa común, no a errores sueltos.
- *[Suposición]* La causa más probable es que faltan las recetas de Talita queso, Marinera, variantes con semillas andinas y Galleta de Naranja, que consumen premezcla y hoy no se imputan. Son sólo el 3,6% de las unidades, pero las galletas y talitas usan mucha más premezcla por unidad que un alfajor. La segunda causa candidata es que se compró para stock. No se puede distinguir entre las dos sin el conteo físico.
- *[Seguro]* El baño de chocolate regular en 1,62 es un caso aparte: ahí la receta declara más de lo que se compra.

---

## 5. Lead time real por proveedor

Calculado sobre 1.548 líneas de OC recibidas. **La columna DEMORA de la planilla de Compras no sirve** para esto: mide atraso contra la fecha prometida, no tiempo de entrega. Se recalculó como fecha de recepción menos fecha de pedido.

| Proveedor | OCs | Mediana | p90 | Máx |
|---|---:|---:|---:|---:|
| NP FLEXIBLES S.A. | 37 | **29 d** | **71 d** | 88 d |
| Acrilux | 33 | 20 d | 34 d | 44 d |
| Productos Alimenticios Harmony | 30 | 12 d | 27 d | 37 d |
| Lecker Argentina | 28 | 9 d | 40 d | 344 d |
| Trini S.A | 39 | 8 d | 24 d | 29 d |
| Agroalimentos Praga | 33 | 7 d | 15 d | 35 d |
| Melar | 27 | 6 d | 9 d | 33 d |
| Sapore di Ciocolatto | 38 | 4 d | 12 d | 45 d |
| Papelera Cumbre | 31 | 3 d | 25 d | 47 d |
| Distribuidora Nicco | 76 | 2 d | 10 d | 17 d |
| Todo Droga | 41 | 2 d | 6 d | 18 d |
| Zoppetti Paola | 34 | 1 d | 5 d | 7 d |

**Consecuencia operativa:** los flexibles tienen p90 de 71 días. Cualquier alerta de flexible que se dispare con menos de 10 semanas de cobertura ya llega tarde. Los ingredientes secos, con 2-6 días, toleran mucho menos stock. Un stock mínimo uniforme —como el "6 semanas para todos" de la planilla de 2023— sobre-stockea lo barato y deja expuesto lo crítico.

---

## 6. Advertencia sobre el conteo semanal

Contar ~230 insumos vigentes todas las semanas son 3-5 horas semanales de una persona, indefinidamente. En la práctica se sostiene 4 a 6 semanas y después se abandona, y cuando se abandona el sistema entero pierde credibilidad.

**Propuesta:** conteo total durante las primeras 4 semanas para medir cuánto se desvía realmente cada insumo. Con esos datos, el sistema puede clasificar solo: los que derivan siguen semanales, el resto pasa a mensual. Se decide con números, no con intuición.

---

## 7. Lo que falta, en orden

| # | Qué | Quién | Bloquea |
|---|---|---|---|
| 1 | **Primer conteo físico** de los insumos vigentes | Planta | Todo. Sin saldo inicial no hay sistema. |
| 2 | Definir depósitos de insumos y responsable de cada uno | Operaciones | El conteo |
| 3 | Recetas faltantes: Talita queso, Marinera, semillas andinas, Alfajor soja | Quien formula | Precisión del consumo |
| 4 | Revisar las recetas de premezcla (ratio 0,23-0,50) | Quien formula | Precisión del consumo |
| 5 | Confirmar el mapeo SKU → material de empaque (rediseño 2026 duplicó códigos) | Compras | Alertas de flexibles |
| 6 | Decidir si se retoma la declaración de masas o se abandona formalmente | Producción | Nada, pero define la precisión techo |
| 7 | Lote mínimo de compra por insumo (hoy es texto libre) | Compras | Sugerencia de cuánto pedir |
| 8 | Unidades por bulto de 3 SKU que no se pudieron deducir | Producción | Consumo de esos SKU |

---

## 8. Fases siguientes

**Fase 1 — Kardex vivo (2-3 semanas después del primer conteo).**
Planilla en Sheets que calcula stock actual por insumo: conteo + recepciones − consumo teórico. Lectura para todos, escritura sólo para quien carga el conteo.

**Fase 2 — Alertas.**
Semáforo por insumo comparando cobertura en días contra el lead time p90 de su proveedor. Crítico cuando la cobertura no alcanza a cubrir el lead time; alerta cuando no cubre lead time + 30%.

**Fase 3 — Previsión.**
Enganche con el Planificador: los bultos a producir se convierten a necesidad de insumos con el mismo motor, y las alertas pasan de "me estoy quedando" a "me voy a quedar el 12 de septiembre".

**Fase 4 — Tablero multiusuario.**
Vista de lectura para las varias personas que necesitan verlo, sin acceso a la planilla de cálculo.

---

## 9. Archivos

- `HappyFood_Stock_Insumos_v1.xlsx` — la base de datos maestra generada en esta fase. 10 hojas. Amarillo = completar a mano.
- Fuentes usadas: `Happy Food - Compras R-COM02`, `Happy Food - PRODUCCIÓN`, `Copia de Control Stock de Insumos.xlsx`, `Happy_Food_Planificador_Produccion`.


---

## 10. Corrección v2 — sí existe el conteo de stock

La primera versión de este documento decía que no había stock de insumos registrado. **Era incorrecto.** Existe `ConteoStockMPyEnvases` (dueño leandrogiomprini@happyfood.com.ar): 117 códigos, conteo semanal desde el 11/06/2026, 12 fechas cargadas. El relevamiento inicial no lo encontró porque el título no contiene la palabra "insumo" y el archivo es de otra cuenta.

**Qué cambia:** no hay que crear el saldo inicial. El sistema puede correr ya.

### La clave: el conteo permite MEDIR el consumo, no estimarlo

Con dos conteos y las recepciones de OC del medio, el consumo sale por diferencia:

```
Consumo del período = Stock inicial + Ingresos de OC − Stock final
```

Esto es independiente del BOM. Se calculó para **116 insumos** sobre el período 11/06 → 13/08. Es un dato mucho más sólido que la receta, porque incluye scrap, mermas y recetas que no están cargadas.

**Consecuencia de diseño:** el consumo medido es la fuente primaria; la receta queda como respaldo para los insumos con pocos conteos y como motor de la *previsión* futura (para proyectar hay que partir del plan productivo, y ahí sí hace falta el BOM).

### El BOM, revalidado contra consumo medido

Comparando la receta contra el consumo realmente medido (no contra las compras, que estaban distorsionadas por un error de unidades):

| Insumo | Medido kg/sem | Receta kg/sem | Receta/Real |
|---|---:|---:|---:|
| Baño Chocolate Diet | 72,2 | 67,1 | 0,93 |
| Dulce de Leche | 186,1 | 159,2 | 0,86 |
| Harina de Maíz | 344,4 | 288,9 | 0,84 |
| Fécula de Papa | 17,9 | 14,9 | 0,83 |
| Fécula de Mandioca | 130,6 | 104,5 | 0,80 |
| Harina de Arroz | 410,0 | 322,1 | 0,79 |
| Baño Chocolate Reg | 195,6 | 149,4 | 0,76 |
| Almidón de Maíz | 419,4 | 314,2 | 0,75 |
| Mousse de Chocolate | 116,0 | 84,6 | 0,73 |
| Aceite Alto Oleico | 320,0 | 208,1 | 0,65 |
| Polidextrosa | 308,3 | 172,1 | 0,56 |
| Sorbitol | 69,8 | 21,1 | 0,30 |
| Trigo Sarraceno | 63,9 | 88,9 | 1,39 |
| Dulce de Leche Diet | 58,3 | 147,7 | 2,53 |

*[Probable]* El BOM subestima entre 15% y 35% de forma sistemática. Eso es consistente con scrap y con las recetas que faltan (Talita queso, Marinera, andinas). No es que las recetas estén mal: es que no cubren todo.

*[Seguro]* Sorbitol (0,30) y Dulce de Leche Diet (2,53) son casos aparte que merecen mirarse uno por uno.

**Esta conclusión reemplaza la del §4**, que estaba basada en las compras y contenía el error de unidades descrito abajo.

---

## 11. Dos errores de datos encontrados

### A · `ConteoStockMPyEnvases` — la columna C muestra 0 mientras se carga el conteo

```
=IF(A4="","",IFERROR(INDEX(D4:ABF4,1,MATCH(MAX($D$3:$ABF$3),$D$3:$ABF$3,0)),""))
```

Busca la fecha más alta de la fila 3. Apenas se escribe la fecha del conteo nuevo, C pasa a leer esa columna aunque todavía esté vacía. Y como la fórmula de cada bloque devuelve 0 cuando los inputs están en blanco, C muestra 0, no vacío.

**Hoy 20/08, con el conteo a medio cargar: 64 de 122 ítems muestran 0 o vacío teniendo stock real.** Flex CLASICA 2026 muestra 0 y tiene 99,05 kg. Aceite A.Oleico muestra vacío y tiene 2.120 kg.

Arreglo, dos cambios:

1. Que la columna calculada de cada bloque devuelva vacío si no se cargó nada:
   - hoy: `=(I5+J5)-(H5*0.6)`
   - debería: `=IF(COUNT(H5:J5)=0,"",(I5+J5)-(H5*0.6))`
   - Igual en los otros bloques: Talitas `=(I34+J34)-(H34*1)`, DISPLAY `=H50*I50`, INSUMOS `=I70`, CAJAS `=(H130*I130)+(H130*J130)`.
2. Que C tome el último valor no vacío:
   `=IF($A4="","",IFERROR(LOOKUP(2,1/($D4:$ABF4<>""),$D4:$ABF4),""))`
3. Aparte: C88 (Esencia Jamón) tiene 17.626 pegado a mano y le rompió la fórmula.

### B · `Compras R-COM02` — la columna "RECEPCION - Cant" mezcla unidades

En **66 de 876 líneas** está cargada en kg o litros en lugar de bolsas o bidones. Ejemplo real, código 9 Almidón de Maíz:

```
03/07/2026 · pedido 40 bolsas (1.000 kg) · recepción cargada: 1000  ← está en kg
27/07/2026 · pedido 40 bolsas (1.000 kg) · recepción cargada: 40    ← está en bolsas
```

Quien lea esa columna sin darse cuenta multiplica por 25 y le da 26 toneladas de almidón en dos meses en lugar de 2. Es exactamente el error que hace que un sistema de alertas grite lobo y la gente deje de mirarlo.

Arreglo: agregar una columna calculada "Recepción en unidad de insumo" y dejar la actual sólo para carga, o poner validación de datos que aclare la unidad.

### C · Otras observaciones

- El primer bloque de fecha del conteo dice 05/06/2025, casi seguro por 05/06/2026.
- Los conteos caen en jueves, no en miércoles (salvo 08/07, 15/07, y 24/07 que es viernes).
- El conteo del 08/07 quedó incompleto: 55 de 117 ítems.
- 5 insumos dan consumo negativo entre junio y agosto — el stock subió sin ingreso de OC registrado: Display Bocadito, Display DDL Reg, Display G Coco, Flex Familiar Naranja 2026 y Flex QUESO 2026. O faltan cargar esas recepciones, o hay error de conteo.
- 26 códigos que se cuentan figuran en Compras como OBSOLETO, VENCIDO o DESARROLLO, entre ellos los baños de chocolate (23 y 24) y los flexibles 2026 (244 a 249). El campo ESTADO del maestro está desactualizado; el conteo refleja mejor qué se usa.
- El conteo cubre 117 códigos. De los insumos que el BOM dice que se consumen, **40 de 42 están cubiertos**. Faltan Pera (147) y el código 1088 de PLASTIDEMIA.

---

## 12. Estado del sistema al 20/08/2026

Con el motor corriendo sobre datos reales:

| Estado | Insumos |
|---|---:|
| 1 · CRÍTICO — la cobertura no cubre el lead time | 23 |
| 1b · en cero, verificar si es real o no se contó | 9 |
| 2 · alerta | 7 |
| 3 · ok | 47 |
| 3b · excedente | 15 |
| 4 · sin consumo calculable | 16 |
| 5 · sin conteo | 223 |

Los más urgentes, por fecha estimada de quiebre:

| Cód | Insumo | Stock hoy | Consumo/sem | Cobertura | LT p90 | Quiebre est. |
|---|---|---:|---:|---:|---:|---|
| 164 | Sorbitol | 4,2 kg | 69,8 kg | 0 d | 6 d | ya |
| 113 | Flexible Galletas Familiar Limón | 0,3 kg | 8,6 kg | 0 d | 71 d | ya |
| 73 | Dulce de Leche | 88,9 kg | 186,1 kg | 3 d | 10 d | 23/08 |
| 23 | Baño Chocolate Semiamargo Reg | 164,4 kg | 195,6 kg | 6 d | 20 d | 26/08 |
| 78 | Esencia de Jamón | 1,6 kg | 1,6 kg | 7 d | 13 d | 27/08 |
| 16 | Bandejas de Galletas Familiar | 10.600 u | 7.400 u | 10 d | 34 d | 30/08 |
| 19 | Bandejas de Alfajores | 14.667 u | 5.133 u | 20 d | 34 d | 09/09 |
| 38 | Cajas Terciarias 375x295x150 | 2.318 u | 682 u | 24 d | 28 d | 13/09 |

*[Suposición]* Varios de estos ya deben estar pedidos y no aparecen porque la OC todavía no se recibió. La lista sirve como control cruzado contra lo que Compras ya tiene en curso, no como orden de compra.

---

## 13. Próximo paso

Lo que sigue no es más análisis: es pasar el motor a Google Sheets con `IMPORTRANGE` desde `ConteoStockMPyEnvases`, `Compras R-COM02` y `Happy Food - PRODUCCIÓN`, para que el semáforo se actualice solo cada vez que se carga un conteo o se recibe una OC. Antes conviene arreglar los dos errores de datos del §11, porque el motor los hereda.


---

## 14. Política de toneladas mensuales (v3)

El semáforo ahora se calcula contra el nivel de producción **planificado**, no contra el actual.

### Toneladas realmente producidas

Calculadas desde el parte de producción con los kg/bulto del Planificador, descontando el doble conteo semielaborado/envasado y excluyendo rearmados:

| Mes | t | Mes | t |
|---|---:|---|---:|
| 2025-09 | 10,90 | 2026-02 | 9,62 |
| 2025-10 | 8,96 | 2026-03 | 9,19 |
| 2025-11 | 8,02 | 2026-04 | 10,30 |
| 2025-12 | 8,74 | 2026-05 | 7,61 |
| 2026-01 | 9,13 | 2026-06 | 9,36 |
| | | 2026-07 | 9,97 |

Promedio de los últimos 11 meses completos: **9,25 t/mes**. En la ventana en que se midió el consumo (11/06 a 13/08) la planta corrió a **9,63 t/mes**.

### El factor de escala

```
Factor = toneladas objetivo del mes ÷ toneladas de la ventana de medición
       = 13,0 ÷ 9,63 = 1,35
```

Todo el consumo medido se multiplica por ese factor. **[Seguro]** Con la política comercial de 13 t/mes, la planta consume 35% más de lo que se midió, y la cobertura real es 35% menor que la aparente:

| Insumo | Cobertura al ritmo actual | Cobertura a 13 t |
|---|---:|---:|
| Dulce de Leche | 3 d | 2 d |
| Baño Chocolate Semiamargo | 6 d | 4 d |
| Bandejas de Galletas Familiar | 10 d | 7 d |
| Bandejas de Alfajores | 20 d | 15 d |
| Bandejas de Talitas | 30 d | 22 d |
| Cajas Terciarias 375x295x150 | 24 d | 18 d |

El estado del semáforo, la fecha de quiebre y la cantidad sugerida a pedir usan la cobertura al plan. La cobertura al ritmo actual queda visible al lado, para comparar.

La toneladas objetivo es un parámetro editable en la hoja `PARAMETROS`: si cambia la estimación comercial, se cambia ahí y recalcula todo.

### Límite conocido de este modelo

**[Seguro]** El factor escala todos los insumos por igual. Eso es correcto sólo si el mix de productos no cambia. Si las toneladas extra vienen concentradas en un producto —una EXPO de alfajores, por ejemplo— el modelo sobrestima el consumo de los insumos de galletas y subestima el de los de alfajor. Para eso hay que proyectar SKU por SKU con el BOM en vez de escalar de forma pareja, y para eso hacen falta las recetas corregidas.

### Nueva hoja: PREVISION_MES

Por insumo: cuánto se necesita para un mes a 13 t, cuánto hay hoy, el gap, y cuánto comprar. No descuenta las OC ya emitidas y todavía no recibidas — eso es lo próximo a conectar.

---

## 15. Pendiente de acceso: las recetas oficiales

El usuario indicó que las recetas de productos terminados y premezclas están en un archivo con la hoja `Receta` y los códigos de insumo en la columna S. **Ese archivo no es accesible desde la cuenta conectada** (`leandrogiomprini@gmail.com`): Drive responde "Requested entity was not found". El conteo de stock sí se pudo abrir y pertenece a `leandrogiomprini@happyfood.com.ar`, así que el archivo de recetas probablemente esté sólo en la cuenta corporativa.

**Qué destraba:** compartirlo con la cuenta de Gmail. Con eso se reemplaza el BOM de dic-2023 —que subestima entre 15% y 35%— por las recetas vigentes, y como ya traen el código de insumo en la columna S se elimina todo el cruce por nombre de texto, que hoy necesita 21 alias manuales.


---

## 16. Recetas oficiales — v4 (20/08/2026)

Con el acceso concedido se procesó `Control Stock de Insumos.xlsx`, hoja **`Recetas`**. Reemplaza al BOM de dic-2023.

### Qué cambió

| | BOM 2023 | Recetas oficiales |
|---|---|---|
| Productos | 12 | **17** |
| Códigos de insumo | ninguno (cruce por nombre, 21 alias a mano) | **columna S, 54 códigos, rango 1-213** |
| Faltaban | Talita queso, Marinera, Andinas, Alfajor soja | **ninguno** |
| Cobertura de la producción | 96,4% de las unidades | **100,0%** |

También cambió el **rinde**, y no poco:

| Producto | Rinde viejo | Rinde oficial |
|---|---:|---:|
| Alfajores (DDL, Chocolate, Maní, S/A, Coco, Soja) | 2.500 u/masa | **2.350** |
| Bocadito | 5.000 | **4.700** |
| Galletas (Naranja, Coco, Pera, Limón) | 1.250 | **1.096** |
| Talita clásica y Talita Andina | 408 | **480** |
| Talita Jamón, Queso, Marinera, Marinera Andina | 408 | 408 |

Otros cambios de fondo: "Chalitas" pasó a llamarse **"Talitas"**, el **BHT se reemplazó por TOCOFEROL**, y aparecen Harina de Soja, semilla de Chía y Oleomargarina.

### Un error de datos que estaba contaminando todo

Al recalcular apareció que **la columna `RECEPCION - Cant` de Compras está cargada de forma inconsistente**: a veces en unidad de compra (bolsas) y a veces ya en kg.

Ejemplo real, Harina de Maíz: la OC 792 y la OC 828 tienen `Cant = 40` bolsas, `Cant. Solicitada = 1.000` kg y `Recepción = 1.000`. Ese 1.000 ya está en kg, pero multiplicado por el factor 25 da 25.000 kg. Dos líneas mal leídas inflaban 50 toneladas.

**[Seguro]** Sin corregir esto, la validación decía que la receta subestimaba entre 4× y 6×. Corregido, la conclusión se da vuelta. Son 66 líneas de 880 en el último año. **La corrección está aplicada en el motor, pero el dato de origen sigue mal cargado en la planilla de Compras** — conviene normalizarlo ahí, porque cualquier cálculo de costos que salga de esa columna arrastra el mismo error.

### La conclusión que reemplaza a "el BOM está mal"

Comparando la receta oficial contra el consumo **medido por diferencia de conteos** (que no depende de ninguna receta):

| Insumo | Consumo medido (kg/sem) | Según receta | Merma implícita |
|---|---:|---:|---:|
| Mousse de Chocolate | 116,0 | 107,2 | **+9%** |
| Baño Chocolate Semiamargo | 195,6 | 171,8 | **+14%** |
| Azúcar impalpable | 40,0 | 34,6 | +15% |
| Dulce de Leche | 186,1 | 160,6 | **+16%** |
| Pasta de Maní | 133,3 | 110,2 | +20% |
| Baño Chocolate Diet | 72,2 | 57,8 | +25% |
| Fécula de Mandioca | 130,6 | 101,0 | +30% |
| Almidón de Maíz | 419,4 | 289,9 | **+45%** |
| Harina de Arroz | 410,0 | 279,7 | **+47%** |
| Harina de Maíz | 344,4 | 222,6 | **+54%** |
| Aceite Alto Oleico | 320,0 | 199,4 | **+61%** |
| Polidextrosa | 308,3 | 190,4 | **+61%** |

**[Seguro]** La receta oficial explica entre el 62% y el 92% del consumo real. No está rota: le falta la merma.

**[Probable]** El patrón no es aleatorio. Los rellenos y baños —que se dosifican con balanza sobre el producto— pierden entre 9% y 25%. Los ingredientes secos de premezcla pierden entre 45% y 61%. Eso es consistente con dónde se pierde materia en una planta: polvo en suspensión, resto de batch en la mezcladora, fondo de bolsa, premezcla que se prepara y no se usa entera.

**[Suposición]** Un 45-61% de merma en harinas es alto incluso para una planta de sin gluten. Los candidatos, en orden de probabilidad: (1) el rinde real por masa es menor que el declarado —si de una masa salen 2.000 unidades y no 2.350, la merma aparente cae del 54% al 31%—; (2) producción para terceros o para Brasil que consume insumo pero no entra al parte —el conteo de stock tiene secciones separadas de "flexibles para Brasil" y "cuenta de elaboración", así que existe ese circuito—; (3) merma genuina de proceso. **No se puede separar sin pesar una masa terminada y contar cuántas unidades salen.** Es una medición de media hora en planta y vale más que cualquier ajuste de fórmula.

### El agujero de Marinera

Las columnas Q y R de la hoja `Recetas` —Marinera y Marinera Andina— apuntan a celdas vacías del bloque de premezcla SALADO. Consumen 11-12 insumos contra los 21 de Talita clásica: **les falta toda la premezcla** (harina de maíz, harina de arroz, almidón, trigo sarraceno, guar, xántica, fécula de mandioca, fécula de papa) más polvo leudante y esencia de manteca.

Hoy no duele: en la ventana medida se produjeron 21 unidades de marinera. **Duele el día que se produzcan en serio.** Es un arreglo de dos celdas en la planilla de recetas.

### Nueva columna: MERMA_IMPLICITA

En la hoja `ALERTAS`, para cada insumo con consumo medido: cuánto más se consume de lo que dice la receta. Es el candidato natural a indicador de eficiencia de planta — si baja, se está desperdiciando menos.

Mientras la merma no esté medida por insumo, **el consumo medido por diferencia de conteos manda sobre el de la receta**, porque incluye la merma sin tener que estimarla. La receta se usa sólo para los insumos que todavía no tienen 4 conteos.


---

## 17. Planificador semanal de compra — v5 (20/08/2026)

Cambia el proceso de referencia. La compra se gestiona **semana a semana**: los viernes se define el plan de producción de la semana siguiente y de ahí sale qué comprar. El estimado mensual sirve para negociar con proveedores, no para pedir.

### La declaración de masas volvió, y eso simplifica el motor

Al 20/08 hay **124 declaraciones nuevas posteriores al 23/06**. Julio, con 65, es el mes con más declaraciones de toda la serie.

Eso permite un cambio de fondo: **el consumo de ingredientes de masa ya no depende del rinde teórico**. Antes había que ir bultos → unidades → rinde → masas, y el rinde era justamente el número dudoso. Ahora se mide directo el factor **kg de producto terminado por masa declarada**:

| Masa | | kg de PT por masa |
|---|---|---:|
| M-002 | Alfajor DDL | 139,3 |
| M-003 | Alfajor dietético | 120,3 |
| M-001 | Alfajor Coco y DDL | 99,9 |
| M-009 | Talita jamón | 64,3 |
| M-008 | Talita clásica y marinera | 63,8 |
| M-007 | Galleta limón | 61,8 |
| M-005 | Galleta pera | 59,7 |
| M-010 | Talita queso | 53,6 |
| M-011 | Galleta naranja y semillas | 51,2 |
| M-004 | Galleta coco | 45,4 |

Medido del 23/05 al 20/08. Es empírico: si el rinde de la planilla está mal cargado, este factor no se entera, porque no lo usa.

### El factor de merma: la parte que hace que el planificador sirva

Comparando la receta oficial contra el consumo medido por diferencia de conteos, al mismo nivel de producción:

**[Seguro] La mediana da 1,42. Comprar por receta sola dejaría un 30% corto todas las semanas.**

Por eso la necesidad va multiplicada por el factor de merma de cada insumo — medido donde hay conteos suficientes, y 1,42 donde todavía no.

Esto también convierte al factor en un **indicador de planta**: si baja, se está desperdiciando menos. Es el primer número que mide eso en Happy Food.

### Qué sale hoy

Plan base = promedio de las últimas 13 semanas: 44 SKU, 6.672 bultos/semana, 2.350 kg/semana.

| Estado | Insumos |
|---|---:|
| 1 · no alcanza la semana | 4 |
| 2 · pedir ahora | 4 |
| 3 · ok | 18 |
| 4 · sobra | 24 |

A pedir este viernes: Baño Chocolate Semiamargo (588 kg), Polidextrosa (185 kg), Esencia de Naranja, de Pera, de Queso, de Jamón, de Vainilla y Limón AT.

### Cómo se calcula cuánto pedir

```
Objetivo de cobertura = lead time real del proveedor + 1 semana
Comprar = (objetivo − semanas que alcanza) × necesidad semanal
```

El lead time sale de las OC realmente recibidas. **No es uniforme y esa es la gracia**: NP Flexibles necesita 11 semanas de cobertura; Todo Droga, 2. Un mínimo parejo para todos sobre-stockea lo barato y deja expuesto lo que tarda dos meses.

### Lo que falta para cerrarlo

1. **Lote mínimo de compra por insumo.** Hoy está en texto libre en Observaciones de Proveedores. Sin eso, la cantidad sugerida hay que redondearla a mano.
2. **Enganche con el Planificador de Producción.** Hoy el plan se carga a mano en `PLAN_SEMANAL`. Debería leerse por IMPORTRANGE desde `PLAN_SEMANAL` del Planificador y quedar automático.
3. **`Unidad por bulto` del maestro de productos está casi vacía** — sólo 6 SKU la tienen cargada. Se dedujo del gramaje de la descripción. Afecta a los insumos que van por unidad (rellenos, baños, flexibles), no a los de masa.
4. **M-012 "xxx"**: 19 masas declaradas en la ventana sin nombre ni producto asociado. La única observación dice "Masa de choco soja". Hay que darle de alta un código real o se pierden esas masas del cálculo.
5. **M-006 está muerta** (última declaración dic-2024) y duplica el nombre de M-011. Sacarla de la lista del formulario.

### Confirmado sobre el rearmado

Columna H = código que se da de alta, columna V = código desarmado que se descuenta. **956 filas de tipo Rearmado, las 956 con el código desarmado cargado.** El dato está completo, así que el rearmado se puede contabilizar sin supuestos. Hoy el motor lo excluye del consumo de masa, que es lo correcto: rearmar no consume receta, sólo empaque.


---

## 18. Auditoría de los tres maestros — v6

Se cruzaron **receta ↔ conteo de stock ↔ maestro de compras**, código por código.

### El hallazgo principal: el empaque no tiene receta

**[Seguro] La planilla de recetas tiene sólo ingredientes. Cero empaque.** Ni flexibles, ni displays, ni bandejas, ni cajas. La versión de 2023 sí los tenía; la oficial los dejó afuera.

Son **51 materiales vigentes** que se cuentan todas las semanas y que ninguna receta consume. Y no son cualquier cosa: **su lead time mediano es de 71 días**, contra 2 a 6 días de los ingredientes secos.

Es decir: el planificador estaba calculando bien justo lo que llega en dos días, y nada de lo que tarda dos meses y medio.

**Arreglo aplicado ahora:** el empaque entra al planificador con su consumo **medido por diferencia de conteos**, no calculado por receta. Funciona, y de hecho al agregarlo la lista de críticos cambió de cara: los primeros seis lugares pasaron a ser flexibles y cajas.

**Límite de ese arreglo:** al no haber receta, si cambia el mix de productos el empaque no se ajusta solo. Cargar el consumo de empaque por SKU en la planilla de recetas es lo que lo cierra del todo.

### Los otros insumos: sí están, con otro nombre

Tocoferol y monoestearato **sí están** en las tres planillas. Lo que pasa es que cada una los llama distinto:

| Código | En la receta | En el conteo | En el maestro de compras |
|---:|---|---|---|
| 30 | TOCOFEROL | Tocoferol | **BHT** |
| 143 | MONOESTEARATO | Monoestearato | Monoestearato de Glicerilo |
| 146 | crema de mani | Pasta de mani | Pasta de Maní |
| 155 | semilla quinoa | Quinoa blanca | Quinoa Blanca |
| 82 | ES.NARANJA (IFF) | Esencia Naranja (IFF) | Esencia de Naranja |
| 85 | ES. DE VAINILLA | Esencia de Vainilla | Esencia de Vainilla |

**14 insumos con nombre distinto en al menos una planilla.** El caso 30 es el peor: el maestro de compras todavía lo llama BHT, que es el aditivo que se dejó de usar. Si alguien busca "tocoferol" en Compras, no aparece.

El código sí es consistente en las tres — por eso el motor no se equivoca. El problema es humano: se busca por nombre.

Nueva hoja **`TODOS_LOS_INSUMOS`**: los 117 códigos con los tres nombres al lado. Si un insumo "no está", ahí se encuentra.

### Unidades: 6 casos, ninguno catastrófico

| Cód | Insumo | Problema |
|---:|---|---|
| 78 | Esencia de Jamón | Se compra en **LT**, la receta está en **KG**, y el factor es 1 a 1: no convierte densidad |
| 135 | Glicerina Alimentaria | Compra en LT, receta en KG, **sin factor** |
| 48 | Colorante Caramelo tipo I | **Falta el factor de conversión** |
| 37 | Caja Terciaria 538x298x223 s/impresión | **Falta la unidad** |
| 23 | Baño Chocolate Semiamargo | Unidad no estándar: `KG (STICKS)` |
| 24 | Baño Chocolate Diet | Unidad no estándar: `KG (STICKS)` |

**[Probable] El caso de la esencia de vainilla que mencionaste no es un error de unidad.** Cód 85: se compra en tambor de 20 KG, la receta está en KG, el factor es 20, el conteo dio 28,7 y la necesidad 4,04 kg/semana. Los tres números son coherentes entre sí. Lo que sí puede pasar es que en planta se cuente en **litros o en envases** y se anote como si fueran kg — con densidad cercana a 1 el error es del 5% y no se nota en ningún control. Vale confirmarlo mirando cómo se cuenta físicamente.

Las que sí tienen un problema real de unidad son **jamón y glicerina**, donde compra y receta están en unidades distintas y el factor no convierte.

### Detector de magnitud

Comparando el consumo medido contra el teórico, dos insumos quedan fuera de escala:

- **Ácido ascórbico**: se consume 6,6× lo que dice la receta.
- **Semillas de chía**: se consume 0,17× — seis veces menos.

**[Suposición]** En ambos el volumen es chico, así que puede ser ruido de conteo. Pero un 6,6× también es la firma típica de una unidad distinta entre el conteo y la receta (gramos contra kilos, por ejemplo). Los dejé marcados en `AUDITORIA` para verificar en planta.

### Cobertura del conteo

**Buena noticia: los 53 ingredientes de receta se cuentan, y 51 de ellos en las 10 fechas completas.** Las excepciones:

- **Azúcar Común (cód 11)**: aparece en 6 conteos, siempre vacío. O no se usa más, o no se cuenta.
- **Esencia de Pera**: 8 de 10.
- **Tocoferol**: 8 de 9.

### Resumen de acciones

| Qué | Cuántos | Dónde se arregla |
|---|---:|---|
| Cargar consumo de empaque por SKU | 59 | Planilla de recetas |
| Unificar nombres entre las tres planillas | 14 | Maestro de Compras (empezando por BHT → Tocoferol) |
| Corregir unidad o factor | 5 | Maestro de Compras |
| Verificar en qué unidad se cuenta | 2 | Planta |
| Completar el conteo | 1 | Planta |

Todo está en la hoja `AUDITORIA`, una fila por problema, con la columna ACCION indicando qué hacer y dónde.
