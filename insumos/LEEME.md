# Insumos y recetas → Supabase (fase 2 y 3 del macroproyecto)

Integración del proyecto de Claude "Stock de insumos en tiempo real" (ago–oct 2026) a la base central.
Revisado el 27/10/2026.

## De dónde sale todo

| Documento | Qué tiene |
|---|---|
| `docs/diseno_stock_insumos.md` | Diseño v1→v6 (20/08/2026): decisiones, validación de recetas contra consumo medido, merma, lead time por proveedor, auditoría de los tres maestros, errores de datos encontrados en las planillas |
| `docs/traspaso_stock_insumos.md` | Traspaso del 22/10/2026: cómo calcula el motor, IDs de las planillas, las 9 reglas aprendidas a fuerza de errores, mapa producto → receta y producto → envases, última corrida, pendientes |
| `docs/traspaso_tablero_produccion.md` | Tablero de producción y stock (otro proyecto, misma planta) |
| `insumos/referencia/apps_script_tablero_insumos/` | Página web del equipo (publica la corrida que deja Claude en Drive) |
| `insumos/referencia/apps_script_tablero_produccion_v2/` | Tablero de producción v2 (lee Pedidos y Control de stock-KG en vivo) |

Los scripts de Python del motor (`pipeline_stock_insumos.py`, `prevision_desde_plan.py`,
`calibrar_envases.py`, `merge_prevision.py`) viven en el proyecto de Claude y no están acá.
La lógica está descripta completa en los dos documentos; la versión en Supabase se escribe en SQL
a partir de esa descripción.

## El problema que resuelve pasarlo a Supabase

El motor funciona, pero (traspaso §8):
1. cada corrida es manual: el tablero envejece entre sesiones (el cuello de botella real);
2. la página web del equipo quedó con datos del 7/10;
3. el mapa de envases (hoja KG) está cableado en el código.

En Supabase el cálculo es una vista que se recalcula sola, igual que las ventas de Tekno.

## Arquitectura propuesta

```
Google Sheets (fuentes, sin cambios para el equipo)
  ConteoStockMPyEnvases · Compras R-COM02 · PRODUCCIÓN · Plan semanal · Control de stock-KG
        │  Apps Script con disparador cada 30 min (cuenta gmail, que ya tiene acceso a todo)
        ▼
Edge Function happyfood-sync-sheets  →  hojas.registros (JSONB crudo, mismo patrón que tekno.registros)
        ▼
core.*  conteos, oc_lineas, recepciones, produccion_partes, produccion_masas, plan_semanal
core.insumos · core.recetas · core.envases_producto   (maestros: se cargan una vez y se editan en la app)
        ▼
calc.stock_insumos   stock hoy, consumo, merma, lead time p80, cobertura con plan, estado
        ▼
rpt / public.reporte_insumos  →  Looker hoy; app de fase 3 después
```

Las recetas (`Control Stock de Insumos.xlsx`) son un .xlsx, que Apps Script no lee en vivo:
se cargan una vez como maestro (`core.recetas`) y a partir de ahí se mantienen en la base.

## Reglas que se trasladan tal cual (traspaso §4)

Pasado real / futuro planificado · flexibles en kg de film con factor calibrado · empaque del tripack
en el 2xxx declarado en bandejas · en el plan se cobra el empaque en el 3xxx · conteos >95% repetidos
se descartan · insumos Inactivo (col AK) fuera · OC de proveedores en desarrollo/obsoletos fuera ·
fecha del plan dd/mm/aaaa · StkEnvasesFlx col E no es bandejas por bulto.

Más las de los datos de Compras: la columna "RECEPCION - Cant" mezcla unidad de compra y kg en
~66 líneas por año (diseño §16): el motor lo corrige; conviene normalizarlo en la planilla.

## Orden de trabajo

1. Sincronizar las planillas a Supabase (Apps Script + Edge Function + `hojas.registros`).
2. Maestros: `core.insumos` (código de Compras, tres nombres, unidad, factor, estado AK),
   `core.recetas` (17 productos × 54 insumos), `core.envases_producto` (traspaso §6).
3. Vistas de movimientos: conteos, recepciones de OC, OC pendientes, producción, masas, plan.
4. `calc.stock_insumos` con la misma lógica del motor; validar contra la corrida del 22/10.
5. Reporte en Looker; en la fase 3, la app reemplaza la carga de conteo y producción.

## Abiertos heredados que siguen vigentes

- Recetas de Marinera y Marinera Andina sin premezcla (diseño §16).
- Empaque sin receta en la planilla oficial: se usa el mapa de envases + consumo medido.
- Códigos 194, 195 y 250 sin marca Activo/Inactivo.
- M-012 "xxx" (masa de choco soja) sin código de masa real.
- Nombres distintos para el mismo código en las tres planillas (30 = Tocoferol, en Compras "BHT").
- Códigos de insumo de Tekno (0000001…) distintos de los de Compras (9 = Almidón): hay que mapearlos
  si se quiere cruzar con las facturas de compra de Tekno.
