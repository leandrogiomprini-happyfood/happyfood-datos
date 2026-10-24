# Diccionario de Tekno · ventas

Fuente: `tekno.ventas` (MOVIVENT.DBF) y `tekno.ventas_detalle` (DETAVENT.DBF).
Relevado el 24/10/2026 a partir de las claves del JSONB (5.937 comprobantes y 29.547 líneas activos, desde 2017-03-10).

Estados: **confirmado** (lo validó Cuci o un comprobante real) · **probable** (lo indican los datos) · **a confirmar**.

## Relación entre tablas

`ventas.ORDEVENT` = `ventas_detalle.ORDECOMP` (probable: mismos rangos 496–15204).

## Tipos de comprobante (CODICOMP)

| Código | Cantidad | Significado | Estado |
| --- | --- | --- | --- |
| F2 | 2.950 | Factura | a confirmar letra / talonario |
| P2 | 1.428 | Presupuesto (no fiscal, sin CAE) | confirmado (P2 1048 del 22/10) |
| C2 | 625 | Nota de crédito | a confirmar |
| F7 | 484 | ¿Factura de crédito electrónica MiPyME? | a confirmar |
| C7 | 193 | ¿Nota de crédito de FCE? | a confirmar |
| A2 / A1 / A3 / A4 | 68 / 65 / 1 / 1 | ? | a confirmar |
| F1 | 53 | Factura (otro talonario) | a confirmar |
| Q2 | 37 | ? | a confirmar |
| D2 | 25 | Nota de débito | a confirmar |
| C1, C5, F3, F8, I2 | 1–3 c/u | ? | a confirmar |

## Encabezado (MOVIVENT)

| Campo | Significado | Estado |
| --- | --- | --- |
| ORDEVENT | Id interno del comprobante | probable |
| CODICOMP | Tipo de comprobante | confirmado |
| TIPOVENT | Letra (A / B) | probable |
| NUMEVENT | 12 dígitos: punto de venta (4) + número (8) | probable |
| FECHVENT / FECHACARGA / HORA | Fecha del comprobante / de carga / hora | probable |
| CODICLIE | Código de cliente | probable |
| CODIVEND | Vendedor | probable |
| CODILIST | Lista de precios | probable |
| CODIFOPA | Forma de pago | probable |
| CODISIFI | Condición fiscal (CF, RI, ...) | probable |
| NETOVENT / NGRAVENT / IMPUVENT / IMPOVENT | Importes: falta saber cuál es neto, gravado y total | a confirmar |
| SALDVENT | Saldo pendiente de cobro | probable |
| NUMECAE / FEVECAE | CAE de AFIP y su vencimiento | probable |
| FECHANUL / HORAANUL | Anulación | probable |
| REMIVENT | Remito asociado | probable |

## Líneas (DETAVENT)

| Campo | Significado | Estado |
| --- | --- | --- |
| ORDEFINA | Id de la línea | probable |
| ORDECOMP | Comprobante al que pertenece | probable |
| CODIARTI | Artículo. `1111111` = DESPACHO (flete, no producto) | probable |
| CANTFINA | Cantidad | probable |
| PRECLIST | Precio de lista | probable |
| BONIFINA | Bonificación % | probable |
| NETOFINA | Neto de la línea. Algunos valores llegan como `****` (desborde del DBF) | confirmado el desborde |
| IMP1FINA / CODIIMP1 | Impuesto 1 y su código (05 ¿IVA 21%?) | a confirmar |
| COSTFINA | Costo (viene en 0) | probable |
