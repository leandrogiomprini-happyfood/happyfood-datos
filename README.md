# HappyFood · datos y sistemas

Repositorio del macroproyecto de datos de HappyFood: base central en Supabase (PostgreSQL),
sincronización desde Tekno, aplicación de carga que reemplaza las planillas y reporting.

El plan vivo del proyecto (fases, decisiones, riesgos) está en el documento
"HappyFood — Macroproyecto de datos y sistemas" en Claude. Acá vive lo técnico.

## Estructura

| Carpeta | Qué hay |
| --- | --- |
| `sync-tekno/piloto` | Sincronizador Tekno → Supabase que corre cada 10 min en SRV-HAPPY (`HappyAuto.cs` + BAT) |
| `sync-tekno/fuentes_originales` | Fuentes del piloto inicial (referencia, no se ejecutan) |
| `sync-tekno/inventario` | Script de solo lectura que lista tablas y campos de los DBF de Tekno |
| `supabase/migrations` | SQL numerado que se aplica en orden sobre Supabase |
| `app` | Aplicación web de carga (fase 2 en adelante) |
| `docs` | Traspasos, diccionario de datos y decisiones técnicas |

## Esquemas en Supabase

- `tekno`: copia cruda (JSONB) de los DBF. Solo la escribe el sincronizador.
- `core`: vistas tipadas sobre `tekno` (números, fechas, signos).
- `ops`: tablas que escribe la aplicación (pedidos, OC, producción, movimientos de stock).
- `rpt`: vistas para tableros y consultas con IA (usuario de solo lectura).

## Reglas

1. Nada de claves, contraseñas, URLs de aviso ni datos exportados en el repositorio (ver `.gitignore`).
2. Todo cambio en la base entra como un archivo nuevo en `supabase/migrations`, nunca editando uno aplicado.
3. El servidor SRV-HAPPY solo extrae de Tekno; la lógica nueva vive en la nube.
