# Tablas de Tekno a sincronizar

Fuente: inventario de encabezados del 24/10/2026 (`sync-tekno/inventario`). 364 DBF en `F:\TEKNO\ssoft.hap\DATOS`;
la gran mayoría están vacías o sin uso desde hace años. Estas son las que se movieron en 2026 y sirven al proyecto.

| Grupo | Tabla | Registros | Qué tiene (probable) | Prioridad |
| --- | --- | --- | --- | --- |
| Ventas | movivent / DETAVENT | 6.068 / 40.037 | Comprobantes de venta y líneas (ya sincronizadas) | hecho |
| Ventas | OBSEVENT | 10.208 | Observaciones de comprobantes (¿N° de pedido u OC del cliente?) | 1 |
| Ventas | AUXIVENC | 5.425 | Vencimientos y saldo por factura | 1 |
| Cobranzas | MOVICOBR / DETACOBR | 3.977 / 10.449 | Recibos y sus medios de pago | 1 |
| Cobranzas | AUXIAPLI | 12.295 | Qué recibo canceló qué factura | 1 |
| Cobranzas | CHEQCOBR | 2.370 | Cheques recibidos | 2 |
| Compras | MOVICOMP / DETACOMP | 6.282 / 15.102 | Facturas de compra y gastos, con proveedor y rubro | 1 |
| Compras | VENCCOMP | 5.213 | Vencimientos de facturas de compra | 2 |
| Pagos | MOVIPAGO / DETAPAGO | 2.954 / 3.765 | Órdenes de pago y medios | 1 |
| Pagos | APLICOMP | 5.405 | Qué pago canceló qué factura de compra | 1 |
| Pagos | CHEQPAGO | 3.146 | Cheques emitidos | 2 |
| Maestros | MAESCLIE | 438 | Clientes, con CUIT, vendedor, lista, zona | 1 |
| Maestros | MAESPROV | 420 | Proveedores, con CUIT y rubro | 1 |
| Maestros | MAESARTI | 200 | Artículos | 1 |
| Maestros | MAESPREC | 2.706 | Precio actual y anterior por artículo y lista | 1 |
| Maestros | MAESCUEN | 245 | Plan de cuentas | 1 |
| Tablas | TABLCOMP, TABLVEND, TABLLIST, TABLFOPA, TABLRUBR, TABLSIFI, TABLTRAN, TABLIMPU, TABLBANC | < 5.400 c/u | Descripciones de códigos | 1 |
| Saldos | SALDCLIE / SALDPROV | 461 / 2.228 | Saldos por período | 2 |

Fuera de alcance por ahora: MOVISTOK / DETASTOK / maesstok (el stock de Tekno no se usa, confirmado el 24/10: el stock vive en Google Sheets; los movimientos que aparecen los genera Tekno solo al facturar), CLIEPERC (percepciones, sin uso desde 2023), BORRADOS (2009), CONCCOMP
(233.628 renglones de texto), movipeve / DETAPEVE (pedidos de venta, sin uso desde julio 2026), tesorería y caja (sin uso desde 2025).

## Diseño propuesto para sumarlas

Una sola tabla genérica en Supabase, `tekno.registros (tabla, registro_origen, datos, eliminado_origen, fecha_sincronizacion)`
con clave `(tabla, registro_origen)`, y una vista por tabla. El sincronizador lee una lista de tablas desde un archivo de
configuración en vez de tenerlas fijas en el código. Agregar una tabla nueva pasa a ser sumar una línea a esa lista.
