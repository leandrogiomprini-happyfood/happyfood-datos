# Sistema de stock y previsión de insumos — Happy Food
## Documento de transferencia (self-contained)

Generado el 2026-10-22. Pensado para que otro proyecto o sesión de Claude pueda retomar
el trabajo sin leer la conversación original. Todo lo que hace falta está acá.

---

## 1. Para qué existe

Happy Food (planta productiva, galletas / alfajores / chalitas sin gluten) necesita:

1. ver el stock de insumos cerca de tiempo real;
2. prever el consumo según el plan de producción fijado;
3. detectar insumos críticos actuales y futuros;
4. que varias personas lo miren a la vez.

Hoy funciona 1, 2 y 3. El 4 está a medias (ver §8).

## 2. Qué existe y dónde

| Pieza | Qué es | Dónde |
|---|---|---|
| `pipeline_stock_insumos.py` | motor principal: stock de hoy, consumo real, lead time, estados | proyecto |
| `prevision_desde_plan.py` | previsión de consumo desde el plan semanal | proyecto |
| `calibrar_envases.py` | mide el consumo real por unidad de envase (unidades y merma) | proyecto |
| `merge_prevision.py` | cruza stock + previsión, recalcula cobertura, arma los lotes para la base | proyecto |
| Tablero | artifact de Claude con base de datos propia | `https://claude.ai/artifact/QQEPokjGeVRmNxUK4nQK83` |
| Página web del equipo | Apps Script publicado desde la cuenta **gmail** | `Codigo.gs` + `Index.html` en el proyecto |

Orden de ejecución: `pipeline` → `calibrar_envases` (opcional, genera `factores_envase.json`)
→ `prevision_desde_plan` → `merge_prevision` → escribir los lotes en la base del artifact.

## 3. Las planillas fuente (IDs de Google Drive)

| Planilla | ID | Hojas y qué se saca |
|---|---|---|
| ConteoStockMPyEnvases | `1hF4u7DKpaoNTH4y9Elo9kE4oNjNjHVpOmZh_saJ9lU8` | `ConteoStock`: fila 3 col G en adelante cada 4 = fechas; col A código, col B nombre; celdas = cantidad contada. Punto de partida del stock |
| Happy Food - Compras R-COM02 | `1RfFVytTdq_UyaIvVn-JoL3nYO391gaxRPPGyVWTOcjU` | `INSUMOS` (nombre, **unidad**); `OC_DETALLE` desde fila 3 (recepciones, OC pendientes, lead time); `INSUMOS_PROV_ALIM`/`NOALIM` col B estado, C cod, K proveedor, M tipo |
| Happy Food - PRODUCCIÓN | `1CZEC7YuURKd6JJKRHyXquVYY-ETB_DOEUT148EqawGA` | `Producción` (D fecha, G tipo, H cod, I descripción, J cantidad); `Producción_Masas` (A fecha, C producto, D cantidad) |
| Control Stock de Insumos.**xlsx** | `1sd7nyXZjGsot2TE91553eYVwPXCfoNbY` | `Recetas` (fila 3 B–R = 17 productos, col S = cod insumo, filas 43–48 = kg por unidad); `Maestro Kg x Producto`; `StkEnvasesFlx` y `Control Stock en Dias` col **AK** Activo/Inactivo |
| Planificación de la producción semanal | `1bmctylGk4K99Nc4e6s4kujyd-ztzbLR6ruzaLa701zs` | `Plan de producción Semanal` desde fila 4: **B fecha, E código, H bultos, J masas** |
| Reporte de pedidos pendientes | `1T1WdLnR6UTDRnlHLf57xYK8twYQ-e1AWODicytga2UY` | hoja `KG` cols I–L = bandeja, display, flexible 1 y 2. **HOY NO SE LEE: está cableada en el código** |

Propiedad: el conteo y el plan son de `leandrogiomprini@happyfood.com.ar`; Compras y
Producción son de `jorgeduardo07@gmail.com` (compartidas); recetas está en una unidad
compartida de Happy Food.

## 4. Cómo se calcula

```
stock_hoy = último conteo completo
          + recepciones de OC posteriores al conteo
          − consumo desde el conteo              (clip en 0)

consumo real de ingredientes = masas declaradas × receta × merma
                             + unidades del parte × receta (rellenos y baños) × merma
consumo real de empaque      = promedio medido entre conteos

previsión (fecha > hoy)      = masas del plan × receta × merma
                             + bultos del plan × envases por bulto × factor de envase

días de cobertura = se descuenta el stock DÍA POR DÍA contra la previsión (no se divide
                    por un promedio, porque el plan es a tirones) y se informa el día en
                    que cruza cero. Detrás del último día del plan se vuelve al promedio
                    de 28 días.

estado: sin stock · crítico (días < lead time) · atención (< LT+14) · ok · sin consumo
lead time = percentil 80 de (recepción − pedido) por código, respaldo por proveedor
```

### Reglas que se descubrieron a fuerza de errores (no las toques sin leer esto)

1. **Pasado real, futuro planificado.** El corte en `hoy` es estricto. El plan nunca
   sobreescribe lo declarado.
2. **Unidades: los flexibles se cuentan en KG de film, las bandejas y displays en unidades.**
   Aplicar la regla de conteo a los flexibles da un error de ~20.000×. Se resuelve con el
   factor calibrado (0,0010–0,0069 kg/unidad = **1 a 7 g de film por unidad**).
3. **El empaque del tripack se consume en el semielaborado 2xxx, no en el 3xxx.** Y el 2xxx
   se declara **en bandejas**, no en bultos (1 bulto = 30 bandejas = 90 unidades). Tomar las
   bandejas como bultos y multiplicar por 30 da un error de dos órdenes.
4. **El plan sólo tiene códigos 3xxx.** Si se le aplica la regla anti-duplicación del
   histórico ("si existe el 2xxx no cobres el 3xxx"), el empaque de alfajores desaparece
   de la previsión en silencio. En el plan se cobra en el 3xxx.
5. **Una columna de conteo que repite >95 % de los valores de la semana anterior se descarta**:
   es copia, no conteo.
6. **Se excluyen los insumos marcados Inactivo** en la columna AK. Es el mecanismo con el que
   se reemplazan los envases viejos por los nuevos diseños.
7. **Se ignoran las OC de proveedores en desarrollo / obsoletos / vencidos**, salvo que el
   insumo no tenga ningún proveedor vigente.
8. **La fecha del plan es dd/mm/aaaa.** Parsear mes-primero convierte el 2 de octubre en
   10 de febrero y la fila desaparece de la previsión sin aviso.
9. **`StkEnvasesFlx` columna E dice "CANT BANDEJAS X BULTO" y NO lo es**: son bandejas por
   caja de compra (1320 para el código 19). Verificable: 48.760 bandejas en 36,94 cajas.

## 5. Mapa código de producto → receta (validado contra datos, 20/20)

3001→DDL · 3011→CHOCOLATE · 3021→MANI · 3041→DDL S/A · 3051→BOCADITO · 3101→Alf coco
3070 y 3073→G NAR sem · 3080 y 3083→Galletas coco · 3090 y 3093→Galletas Pera
3110 y 3113→Galleta Limon · 3121→Talitas clasicas · 3131→Talitas Jamon
3141→Talitas Queso · 3161→Talita Andina · 3153→Marinera · 3173→Marinera Andina

Familiar y galleta individual comparten receta por par: misma masa, distinto formato.
Se deriva en cada corrida de la descripción en `Producción`, no se cablea.

## 6. Mapa de envases

| Producto | Bandeja | Display | Flex 1 | Flex 2 |
|---|---|---|---|---|
| 3001 / 3011 / 3021 / 3041 / 3101 / 3051 | 19 | — | 103 / 109 / 108 / 104 / 101 / 102 | 117 / 118 / 119 / 116 / 114 / 115 |
| 3070 / 3080 / 3090 / 3110 | — | 258 / 57 / 60 / 61 | 238 / 105 / 107 / 128 | — |
| 3073 / 3083 / 3093 | 16 | — | 241 / 240 / 242 | — |
| 3113 / 3153 / 3173 | 17 | — | 243 / 244 / 245 | — |
| 3121 / 3131 / 3141 / 3161 | 15 | — | 246 / 247 / 248 / 249 | — |

Cantidades por bulto, declaradas por el usuario:

| Grupo | Bandejas o displays | Flex 1 | Flex 2 |
|---|---|---|---|
| Tripack (alfajores **y bocadito**) | 30 bandejas | 90 | 30 |
| Galleta individual | 12 displays | 144 | — |
| Familiar y marinera familiar | 20 bandejas | 20 | — |
| Chalita | 24 bandejas | 24 | — |

El flex 2 existe sólo en los tripack: uno por alfajor individual, otro para la bandeja que
los envuelve.

## 7. Última corrida (22/10/2026 13:15)

```
104 insumos · último conteo 15/10 · producción y masas al 21/10 · merma 1,18
plan cargado del 23 al 29/10 (9 filas futuras, 5 días de producción)

sin plan:  1 sin stock · 21 crítico ·  8 atención · 68 ok · 6 sin consumo
con plan:  1 sin stock · 23 crítico ·  8 atención · 67 ok · 5 sin consumo
```

Se agravan con el plan: 73 Dulce de leche (16→5 d) · 143 Monoestearato (12→6) ·
74 Dulce de leche diet (47→21) · 109 Flex Ind Mousse (63→41) · 117 Flex Tripack DDL Reg
(64→43) · 150 Polvo leudante, 23 Baño chocolate y 188 Azúcar impalpable (a 21 d).

## 8. Lo que queda abierto

1. **Leer la hoja KG en cada corrida** en vez de tenerla cableada. Los diseños de flexibles
   cambian este año; con el mapa fijo el motor va a descontar el envase viejo sin avisar.
2. **Actualización automática.** Hoy cada corrida es manual y depende de que alguien la pida.
   Sin una tarea programada diaria, el tablero envejece entre sesiones. Es el cuello de
   botella real del proyecto.
3. **Página web del equipo desactualizada.** El Apps Script publica desde la cuenta gmail
   (el Workspace de happyfood bloquea el scope de Drive). Tiene datos del 7/10 y no muestra
   la previsión: hay que aplicarle los mismos parches que al tablero y volver a subir los
   datos a Drive en trozos de ~4.400 caracteres (más grande, un clasificador corta la carga).
4. **Conteos de empaque que no se mueven.** Hay semanas con producción donde el conteo del
   envase queda idéntico. El motor lo marca (`conteo_repetido`) pero distorsiona la medición.
   El display de naranja mide 2,37× lo esperado; el de limón 0,30×.
5. **Códigos 194, 195 y 250** siguen sin marca Activo/Inactivo en la columna AK.
6. **El gramaje de las chalitas bajó de 120 g a 100 g** durante 2026. El maestro de kg está
   bien para hoy, pero la merma se calibra con 84 días de historia y puede quedar sesgada.

## 9. Mecánica del tablero (artifact)

La página lee una base de datos propia. `tablero/meta` dice qué colección tiene la corrida
vigente (`corridas/<CORRIDA_ID>/insumos`). Cada actualización:

1. escribe los insumos nuevos en una colección nueva (documentos nuevos, sin versión);
2. reemplaza `tablero/meta` fijando `if_version` con la versión leída → el tablero cambia de golpe;
3. borra los documentos de la corrida anterior (`if_version: 1`).

Lotes de 50 escrituras como máximo. Si una corrida falla a mitad, no se toca `meta` y el
tablero sigue mostrando la anterior.
