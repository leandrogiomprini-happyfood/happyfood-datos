# Diccionario de Tekno · ventas

Fuente: `tekno.ventas` (MOVIVENT.DBF) y `tekno.ventas_detalle` (DETAVENT.DBF).
Relevado el 24/10/2026 a partir de las claves del JSONB (5.937 comprobantes y 29.547 líneas activos, desde 2017-03-10).

Estados: **confirmado** (lo validó Cuci o un comprobante real) · **probable** (lo indican los datos) · **a confirmar**.

## Relación entre tablas

`ventas.ORDEVENT` = `ventas_detalle.ORDECOMP` (probable: mismos rangos 496–15204).

## Tipos de comprobante (CODICOMP)

Confirmados por Cuci el 24/10/2026. La tabla de Tekno `TABLCOMP.DBF` tiene la descripción oficial y el código AFIP de cada uno: sincronizarla en la fase 1.

| Código | Cantidad | Significado | Signo | Cuenta como venta |
| --- | --- | --- | --- | --- |
| F2 | 2.950 | Factura | + | sí |
| P2 | 1.428 | Presupuesto (venta sin factura) | + | sí, no fiscal |
| C2 | 625 | Nota de crédito | − | sí |
| F7 | 484 | Factura de crédito electrónica | + | sí |
| C7 | 193 | Nota de crédito (de FCE) | − | sí |
| A2 | 68 | Ajuste de débito | + | no (solo cuenta corriente) |
| A1 | 65 | Ajuste de crédito | − | no (solo cuenta corriente) |
| F1 | 53 | Factura de contado / consumidor final | + | sí |
| Q2 | 37 | Nota de crédito de un presupuesto | − | sí, no fiscal |
| D2 | 25 | Nota de débito | + | sí |
| C1 | 3 | Nota de crédito | − | sí |
| F3, F8, C5, A3, A4, I2 | 1 c/u | Sin confirmar | 0 | no |

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
| NETOVENT | Neto sin IVA | confirmado (FC 0003-00002526: 1.740.831,23) |
| NGRAVENT | Neto gravado | confirmado (igual al neto en esa factura) |
| IMPUVENT | IVA | confirmado (365.574,56) |
| IMPOVENT | Total con IVA | confirmado (2.106.405,76) |
| SALDVENT | Saldo pendiente de cobro | probable (igual al total en una factura impaga) |
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
| NETOFINA | Neto de la línea. Algunos valores llegan como `****` (desborde del DBF) | confirmado: 3 de 29.547 líneas |
| IMP1FINA / CODIIMP1 | Impuesto 1 y su código (05 ¿IVA 21%?) | a confirmar |
| COSTFINA | Costo (viene en 0) | probable |
