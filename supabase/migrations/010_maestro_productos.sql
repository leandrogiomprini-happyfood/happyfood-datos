-- 010_maestro_productos.sql
-- Maestro unico de productos terminados (fase 2). Fuentes:
--   * Indice de productos de Jorge ("Happy Food - Listado de productos", Indice v2, Rev.00 17/06/2025):
--     familia, envase y unidades por codigo.
--   * Articulos de Tekno (MAESARTI) y ventas reales en Supabase (27/10/2026).
--   * Decisiones de Cuci (27/10/2026, Productos_Tekno_vs_Indice.xlsx): vigente / obsoleto.
-- Los productos que no estan en el Indice (Marineras, Talita Andina, soja, Mixto x36) se cargaron con la
-- descripcion de Tekno. Unidades de los bultos 3153 y 3173 sin confirmar (quedan en null = sin kilos).
-- Agrega a los reportes de ventas: familia, unidades y kilos. Se puede volver a ejecutar sin riesgo.
-- Para corregir un dato: update core.productos set ... where codigo = '3153'; select calc.refrescar_rpt();

create table if not exists core.productos (
  codigo         text primary key,                  -- como en el Indice: '3006'
  codigo_tekno   text not null unique,              -- como en Tekno: '0003006'
  familia        text,
  producto       text not null,
  nivel          text not null check (nivel in ('unidad','display','bandeja','bulto')),
  envase         text,
  unidades_por   numeric check (unidades_por > 0),  -- unidades individuales que contiene el codigo
  gramos_unidad  numeric check (gramos_unidad > 0),
  kg_por         numeric generated always as (unidades_por * gramos_unidad / 1000) stored,
  estado         text not null check (estado in ('vigente','obsoleto')),
  en_indice      boolean not null,
  actualizado    timestamptz not null default now()
);
alter table core.productos enable row level security;
revoke all on core.productos from anon, authenticated;

insert into core.productos
  (codigo, codigo_tekno, familia, producto, nivel, envase, unidades_por, gramos_unidad, estado, en_indice)
values
  ('1000', '0001000', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería', 'unidad', 'UNIDAD ALFAJOR 50 G', 1, 50, 'vigente', true),
  ('1010', '0001010', 'Alfajor', 'Alfajor con relleno de mousse chocolate cubierto con baño de reposteria- libre de gluten', 'unidad', 'UNIDAD ALFAJOR 50 G', 1, 50, 'vigente', true),
  ('1020', '0001020', 'Alfajor', 'Alfajor con relleno de pasta de maní cubierto con baño de repostería- libre de gluten', 'unidad', 'UNIDAD ALFAJOR 50 G', 1, 50, 'vigente', true),
  ('1030', '0001030', null, 'EX ALF SIN AZUCAR HASTA 31 DE AGOSTO', 'unidad', null, null, null, 'obsoleto', false),
  ('1040', '0001040', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería - Alimento dietetico- libre de gluten- sin adicion de azucares', 'unidad', 'UNIDAD ALFAJOR 50 G', 1, 50, 'vigente', true),
  ('1050', '0001050', 'Bocadito', 'Bocadito con relleno de dulce de leche cubierto con baño de reposteria- alimento dietetico- libre de gluten- sin adicion de azucares', 'unidad', 'UNIDAD BOCADITO 40 G', 1, 40, 'vigente', true),
  ('1060', '0001060', null, 'Galleta naranja bañada', 'unidad', null, null, null, 'obsoleto', false),
  ('1070', '0001070', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'unidad', 'UNIDAD GALLETITAS 44 G', 1, 44, 'vigente', true),
  ('1073', '0001073', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - FAMILIAR', 'unidad', 'UNIDAD GALLETITAS FAMILIAR 120 G', 1, 120, 'vigente', true),
  ('1080', '0001080', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'unidad', 'UNIDAD GALLETITAS 44 G', 1, 44, 'vigente', true),
  ('1083', '0001083', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - FAMILIAR', 'unidad', 'UNIDAD GALLETITAS FAMILIAR 120 G', 1, 120, 'vigente', true),
  ('1090', '0001090', 'Galletitas', 'Galletitas dulces con pera y canela- alimento dietetico- libre de gluten- sin adicion de azucares- INDIVIDUALES', 'unidad', 'UNIDAD GALLETITAS 44 G', 1, 44, 'vigente', true),
  ('1093', '0001093', 'Galletitas', 'Galletitas dulces con pera y canela- alimento dietetico- libre de gluten- sin adicion de azucares- FAMILIAR', 'unidad', 'UNIDAD GALLETITAS FAMILIAR 120 G', 1, 120, 'vigente', true),
  ('1100', '0001100', 'Alfajor', 'Alfajor con coco y relleno de dulce de leche cubierto con baño de reposteria- Alimento dietético- Libre de gluten- Sin adición de azúcares', 'unidad', 'UNIDAD ALFAJOR 50 G', 1, 50, 'vigente', true),
  ('1110', '0001110', 'Galletitas', 'Galletita dulce sabor a limon - INDIVIDUAL', 'unidad', 'UNIDAD GALLETITAS 44 G', 1, 44, 'vigente', true),
  ('1113', '0001113', 'Galletitas', 'Galletita dulce sabor a limon - FAMILIAR', 'unidad', 'UNIDAD GALLETITAS FAMILIAR 120 G', 1, 120, 'vigente', true),
  ('1121', '0001121', 'Talitas', 'Talita Clasica', 'unidad', 'UNIDAD CHALITAS 100 G', 1, 100, 'vigente', true),
  ('1131', '0001131', 'Talitas', 'Talita Jamon', 'unidad', 'UNIDAD CHALITAS 100 G', 1, 100, 'vigente', true),
  ('1141', '0001141', 'Talitas', 'Talitas Queso', 'unidad', 'UNIDAD TALITAS 100 G', 1, 100, 'vigente', true),
  ('1150', '0001150', 'Marineras', 'MARINERA CLASICA S/GLUTEN PAQ 20GR', 'unidad', 'UNIDAD MARINERA 20 G', 1, 20, 'vigente', false),
  ('1153', '0001153', 'Marineras', 'MARINERA FAMILIAR CLÁSICA S/GLUT PAQ70', 'unidad', 'UNIDAD MARINERA FAMILIAR 70 G', 1, 70, 'vigente', false),
  ('1161', '0001161', 'Talitas', 'TALITA ANDINA S/GLUTEN PAQ 90GR', 'unidad', 'UNIDAD TALITA ANDINA 90 G', 1, 90, 'vigente', false),
  ('1170', '0001170', 'Marineras', 'MARINERA ANDINA S/GLUTEN PAQ 20GR', 'unidad', 'UNIDAD MARINERA ANDINA 20 G', 1, 20, 'vigente', false),
  ('1173', '0001173', 'Marineras', 'MARINERA FAMILIAR ANDINA S/GLUTEN PAQ', 'unidad', 'UNIDAD MARINERA FAMILIAR ANDINA 70 G', 1, 70, 'vigente', false),
  ('2000', '0002000', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 50, 'vigente', true),
  ('2001', '0002001', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 50, 'obsoleto', true),
  ('2010', '0002010', 'Alfajor', 'Alfajor con relleno de mousse chocolate cubierto con baño de reposteria- libre de gluten', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 50, 'vigente', true),
  ('2011', '0002011', 'Alfajor', 'Alfajor con relleno de mousse chocolate cubierto con baño de reposteria- libre de gluten', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 50, 'obsoleto', true),
  ('2020', '0002020', 'Alfajor', 'Alfajor con relleno de pasta de maní cubierto con baño de repostería- libre de gluten', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 50, 'vigente', true),
  ('2021', '0002021', 'Alfajor', 'Alfajor con relleno de pasta de maní cubierto con baño de repostería- libre de gluten', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 50, 'obsoleto', true),
  ('2030', '0002030', 'Alfajor', 'Alfajor Mixto - Dulce de leche, Crema de Maní y Mousse chocolate', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 50, 'obsoleto', true),
  ('2040', '0002040', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería - Alimento dietetico- libre de gluten- sin adicion de azucares', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 50, 'vigente', true),
  ('2041', '0002041', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería - Alimento dietetico- libre de gluten- sin adicion de azucares', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 50, 'obsoleto', true),
  ('2050', '0002050', 'Bocadito', 'Bocadito con relleno de dulce de leche cubierto con baño de reposteria- alimento dietetico- libre de gluten- sin adicion de azucares', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 40, 'obsoleto', true),
  ('2051', '0002051', 'Bocadito', 'Bocadito con relleno de dulce de leche cubierto con baño de reposteria- alimento dietetico- libre de gluten- sin adicion de azucares', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 40, 'obsoleto', true),
  ('2060', '0002060', null, 'CAJA EXHIBIDORA GALLETA BAÑADA SIN AZU', 'display', null, null, null, 'obsoleto', false),
  ('2070', '0002070', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 44, 'obsoleto', true),
  ('2071', '0002071', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 44, 'obsoleto', true),
  ('2080', '0002080', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 44, 'obsoleto', true),
  ('2081', '0002081', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 44, 'obsoleto', true),
  ('2090', '0002090', 'Galletitas', 'Galletitas dulces con pera y canela- alimento dietetico- libre de gluten- sin adicion de azucares- INDIVIDUALES', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 44, 'obsoleto', true),
  ('2091', '0002091', 'Galletitas', 'Galletitas dulces con pera y canela- alimento dietetico- libre de gluten- sin adicion de azucares- INDIVIDUALES', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 44, 'obsoleto', true),
  ('2100', '0002100', 'Alfajor', 'Alfajor con coco y relleno de dulce de leche cubierto con baño de reposteria- Alimento dietético- Libre de gluten- Sin adición de azúcares', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 50, 'vigente', true),
  ('2101', '0002101', 'Alfajor', 'Alfajor con coco y relleno de dulce de leche cubierto con baño de reposteria- Alimento dietético- Libre de gluten- Sin adición de azúcares', 'bandeja', 'BANDEJA CONTIENE 3 UNIDADES (TRIPACK)', 3, 50, 'obsoleto', true),
  ('2110', '0002110', 'Galletitas', 'Galletita dulce sabor a limon - INDIVIDUAL', 'display', 'DISPLAY CONTIENE 12 UNIDADES', 12, 44, 'vigente', true),
  ('3000', '0003000', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 50, 'vigente', true),
  ('3001', '0003001', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería', 'bulto', 'BULTO SUPERMERDADO CONTIENE 30 BANDEJAS 90 UNIDADES EN TOTAL', 90, 50, 'vigente', true),
  ('3002', '0003002', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 50, 'vigente', true),
  ('3006', '0003006', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 50, 'vigente', true),
  ('3010', '0003010', 'Alfajor', 'Alfajor con relleno de mousse chocolate cubierto con baño de reposteria- libre de gluten', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 50, 'vigente', true),
  ('3011', '0003011', 'Alfajor', 'Alfajor con relleno de mousse chocolate cubierto con baño de reposteria- libre de gluten', 'bulto', 'BULTO SUPERMERDADO CONTIENE 30 BANDEJAS 90 UNIDADES EN TOTAL', 90, 50, 'vigente', true),
  ('3012', '0003012', 'Alfajor', 'Alfajor con relleno de mousse chocolate cubierto con baño de reposteria- libre de gluten', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 50, 'vigente', true),
  ('3014', '0003014', 'Alfajor', 'BULTO ALF. MOUSSE CHOCO S/GLUTEN X 24', 'bulto', 'BULTO 24 UNIDADES (codigo viejo)', 24, 50, 'obsoleto', false),
  ('3016', '0003016', 'Alfajor', 'Alfajor con relleno de mousse chocolate cubierto con baño de reposteria- libre de gluten', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 50, 'vigente', true),
  ('3020', '0003020', 'Alfajor', 'Alfajor con relleno de pasta de maní cubierto con baño de repostería- libre de gluten', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 50, 'vigente', true),
  ('3021', '0003021', 'Alfajor', 'Alfajor con relleno de pasta de maní cubierto con baño de repostería- libre de gluten', 'bulto', 'BULTO SUPERMERDADO CONTIENE 30 BANDEJAS 90 UNIDADES EN TOTAL', 90, 50, 'vigente', true),
  ('3022', '0003022', 'Alfajor', 'Alfajor con relleno de pasta de maní cubierto con baño de repostería- libre de gluten', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 50, 'vigente', true),
  ('3024', '0003024', 'Alfajor', 'BULTO ALF.PASTA DE MANI S/GLUTEN x 24', 'bulto', 'BULTO 24 UNIDADES (codigo viejo)', 24, 50, 'obsoleto', false),
  ('3026', '0003026', 'Alfajor', 'Alfajor con relleno de pasta de maní cubierto con baño de repostería- libre de gluten', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 50, 'vigente', true),
  ('3030', '0003030', 'Alfajor', 'Alfajor Mixto - Dulce de leche, Crema de Maní y Mousse chocolate', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 50, 'vigente', true),
  ('3036', '0003036', 'Alfajor', 'BULTO ALF. MIXTO X36 UNID', 'bulto', 'BULTO SUPERMERCADO 36 UNIDADES', 36, 50, 'vigente', false),
  ('3040', '0003040', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería - Alimento dietetico- libre de gluten- sin adicion de azucares', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 50, 'vigente', true),
  ('3041', '0003041', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería - Alimento dietetico- libre de gluten- sin adicion de azucares', 'bulto', 'BULTO SUPERMERDADO CONTIENE 30 BANDEJAS 90 UNIDADES EN TOTAL', 90, 50, 'vigente', true),
  ('3042', '0003042', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería - Alimento dietetico- libre de gluten- sin adicion de azucares', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 50, 'vigente', true),
  ('3044', '0003044', 'Alfajor', 'BULTO ALF. DDL S/GLUTEN  Y DIET. x 24', 'bulto', 'BULTO 24 UNIDADES (codigo viejo)', 24, 50, 'obsoleto', false),
  ('3046', '0003046', 'Alfajor', 'Alfajor con relleno de dulce de leche cubierto con baño de repostería - Alimento dietetico- libre de gluten- sin adicion de azucares', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 50, 'vigente', true),
  ('3050', '0003050', 'Bocadito', 'Bocadito con relleno de dulce de leche cubierto con baño de reposteria- alimento dietetico- libre de gluten- sin adicion de azucares', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 40, 'vigente', true),
  ('3051', '0003051', 'Bocadito', 'Bocadito con relleno de dulce de leche cubierto con baño de reposteria- alimento dietetico- libre de gluten- sin adicion de azucares', 'bulto', 'BULTO SUPERMERDADO CONTIENE 30 BANDEJAS 90 UNIDADES EN TOTAL', 90, 40, 'vigente', true),
  ('3052', '0003052', 'Bocadito', 'Bocadito con relleno de dulce de leche cubierto con baño de reposteria- alimento dietetico- libre de gluten- sin adicion de azucares', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 40, 'obsoleto', true),
  ('3054', '0003054', 'Bocadito', 'BULTO BOCADITO DDL MANI S/GLUTEN Y DIE', 'bulto', 'BULTO 24 UNIDADES (codigo viejo)', 24, 40, 'obsoleto', false),
  ('3056', '0003056', 'Bocadito', 'Bocadito con relleno de dulce de leche cubierto con baño de reposteria- alimento dietetico- libre de gluten- sin adicion de azucares', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 40, 'vigente', true),
  ('3060', '0003060', null, 'BULTO GALLETAS BAÑADAS DE NARANJA S/AZ', 'bulto', null, null, null, 'obsoleto', false),
  ('3070', '0003070', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 44, 'vigente', true),
  ('3071', '0003071', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bulto', 'BULTO SUPERMERDADO CONTIENE 28 BANDEJAS 84 UNIDADES EN TOTAL', 84, 44, 'obsoleto', true),
  ('3072', '0003072', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 44, 'vigente', true),
  ('3073', '0003073', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - FAMILIAR', 'bulto', 'BULTO FAMILIAR CONTIENE 20 UNIDADES EN TOTAL', 20, 120, 'vigente', true),
  ('3076', '0003076', 'Galletitas', 'Galletitas dulces con sésamo y quinoa sabor naranja- alimento ditetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 44, 'vigente', true),
  ('3080', '0003080', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 44, 'vigente', true),
  ('3081', '0003081', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bulto', 'BULTO SUPERMERDADO CONTIENE 28 BANDEJAS 84 UNIDADES EN TOTAL', 84, 44, 'obsoleto', true),
  ('3082', '0003082', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 44, 'vigente', true),
  ('3083', '0003083', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - FAMILIAR', 'bulto', 'BULTO FAMILIAR CONTIENE 20 UNIDADES EN TOTAL', 20, 120, 'vigente', true),
  ('3086', '0003086', 'Galletitas', 'Galletitas dulces de coco- alimento dietetico- libre de gluten- sin adicion de azucares - INDIVIDUALES', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 44, 'vigente', true),
  ('3090', '0003090', 'Galletitas', 'Galletitas dulces con pera y canela- alimento dietetico- libre de gluten- sin adicion de azucares- INDIVIDUALES', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 44, 'vigente', true),
  ('3091', '0003091', 'Galletitas', 'BULTO GALL. PERA S/TACC S/AZUCAR x 28', 'bulto', 'BULTO 28 BANDEJAS 84 UNIDADES (codigo viejo)', 84, 44, 'obsoleto', false),
  ('3092', '0003092', 'Galletitas', 'Galletitas dulces con pera y canela- alimento dietetico- libre de gluten- sin adicion de azucares- INDIVIDUALES', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 44, 'vigente', true),
  ('3093', '0003093', 'Galletitas', 'Galletitas dulces con pera y canela- alimento dietetico- libre de gluten- sin adicion de azucares- FAMILIAR', 'bulto', 'BULTO FAMILIAR CONTIENE 20 UNIDADES EN TOTAL', 20, 120, 'vigente', true),
  ('3095', '0003095', 'Galletitas', 'B.GALL.FAM.PERA S/GLUT., P.120g X 16u', 'bulto', 'BULTO FAMILIAR 16 UNIDADES (codigo viejo)', 16, 120, 'obsoleto', false),
  ('3096', '0003096', 'Galletitas', 'Galletitas dulces con pera y canela- alimento dietetico- libre de gluten- sin adicion de azucares- INDIVIDUALES', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 44, 'vigente', true),
  ('3100', '0003100', 'Alfajor', 'Alfajor con coco y relleno de dulce de leche cubierto con baño de reposteria- Alimento dietético- Libre de gluten- Sin adición de azúcares', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 50, 'vigente', true),
  ('3101', '0003101', 'Alfajor', 'Alfajor con coco y relleno de dulce de leche cubierto con baño de reposteria- Alimento dietético- Libre de gluten- Sin adición de azúcares', 'bulto', 'BULTO SUPERMERDADO CONTIENE 30 BANDEJAS 90 UNIDADES EN TOTAL', 90, 50, 'vigente', true),
  ('3102', '0003102', 'Alfajor', 'Alfajor con coco y relleno de dulce de leche cubierto con baño de reposteria- Alimento dietético- Libre de gluten- Sin adición de azúcares', 'bulto', 'BULTO SUPERMERCADO CONTIENE 2 DISPLAY 24 UNIDADES EN TOTAL', 24, 50, 'vigente', true),
  ('3104', '0003104', 'Alfajor', 'BULTO ALF. COCO Y DDL S/GLUTEN Y DIET.', 'bulto', 'BULTO 24 UNIDADES (codigo viejo)', 24, 50, 'obsoleto', false),
  ('3106', '0003106', 'Alfajor', 'Alfajor con coco y relleno de dulce de leche cubierto con baño de reposteria- Alimento dietético- Libre de gluten- Sin adición de azúcares', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 50, 'vigente', true),
  ('3110', '0003110', 'Galletitas', 'Galletita dulce sabor a limon - INDIVIDUAL', 'bulto', 'BULTO DISTRIBIDOR CONTIENE 12 DISPLAYS 144 UNIDADES EN TOTAL', 144, 44, 'vigente', true),
  ('3113', '0003113', 'Galletitas', 'Galletita dulce sabor a limon - FAMILIAR', 'bulto', 'BULTO FAMILIAR CONTIENE 20 UNIDADES EN TOTAL', 20, 120, 'vigente', true),
  ('3115', '0003115', 'Galletitas', 'B.GALL.FAM.LIMON S/GLUT., P.120g X 16u', 'bulto', 'BULTO FAMILIAR 16 UNIDADES (codigo viejo)', 16, 120, 'obsoleto', false),
  ('3116', '0003116', 'Galletitas', 'Galletita dulce sabor a limon - INDIVIDUAL', 'bulto', 'BULTO SUPERMERCADO CONTIENE 3 DISPLAY 36 UNIDADES EN TOTAL', 36, 44, 'vigente', true),
  ('3121', '0003121', 'Talitas', 'Talita Clasica', 'bulto', 'BULTO FAMILIAR CONTIENE 24 UNIDADES EN TOTAL', 24, 100, 'vigente', true),
  ('3131', '0003131', 'Talitas', 'Talita Jamon', 'bulto', 'BULTO FAMILIAR CONTIENE 24 UNIDADES EN TOTAL', 24, 100, 'vigente', true),
  ('3141', '0003141', 'Talitas', 'Talitas Queso', 'bulto', 'BULTO FAMILIAR CONTIENE 24 UNIDADES EN TOTAL', 24, 100, 'vigente', true),
  ('3153', '0003153', 'Marineras', 'BULTO GALL. MARINERA FAM. CLÁSICA S/GL', 'bulto', 'BULTO FAMILIAR (unidades a confirmar)', null, 70, 'vigente', false),
  ('3161', '0003161', 'Talitas', 'BULTO BAND TALITA ANDINA S/G X24 P90GR', 'bulto', 'BULTO FAMILIAR 24 UNIDADES', 24, 90, 'vigente', false),
  ('3173', '0003173', 'Marineras', 'BULTO GALL MARINERA FAM ANDINA S/G X70', 'bulto', 'BULTO FAMILIAR (unidades a confirmar)', null, 70, 'vigente', false),
  ('8001', '0008001', 'Alfajor', 'CAJA EXHIBIDORA ALF. SOJA DDL X12UN', 'display', 'DISPLAY 12 UNIDADES', 12, 50, 'vigente', false),
  ('9000', '0009000', 'Alfajor', 'BULTO ALFAJOR SOJA DDLX50GRX144UNID.', 'bulto', 'BULTO DISTRIBUIDOR 144 UNIDADES', 144, 50, 'vigente', false),
  ('9001', '0009001', 'Alfajor', 'BULTO ALFAJOR SOJA DDL X50GR X144UNID.', 'bulto', 'BULTO DISTRIBUIDOR 144 UNIDADES', 144, 50, 'vigente', false)
on conflict (codigo) do update set
  codigo_tekno = excluded.codigo_tekno, familia = excluded.familia, producto = excluded.producto,
  nivel = excluded.nivel, envase = excluded.envase, unidades_por = excluded.unidades_por,
  gramos_unidad = excluded.gramos_unidad, estado = excluded.estado, en_indice = excluded.en_indice,
  actualizado = now();

-- Ventas con familia, unidades y kilos (columnas nuevas al final; las anteriores no cambian).
create or replace view calc.ventas_analisis as
with cab as materialized (
  select v.orden, v.fecha, v.signo, v.tipo_comprobante, v.es_fiscal, v.neto,
         v.punto_venta, v.numero, v.cliente_codigo, v.vendedor_codigo
  from core.ventas_vigentes v
  where v.cuenta_como_venta
), det as materialized (
  select d.orden, d.articulo_codigo, d.es_despacho, d.cantidad, d.neto, d.neto_desbordado
  from core.ventas_detalle d
  where not d.eliminado_origen
), lineas as (
  select c.*, d.articulo_codigo, d.es_despacho,
         abs(d.cantidad) * c.signo as cantidad_linea,
         -- Presupuestos (no fiscales): las lineas se ajustan para sumar el total del comprobante (007).
         abs(d.neto) * c.signo * case when c.es_fiscal then 1
           else coalesce(c.neto / nullif(sum(abs(d.neto)) over (partition by c.orden), 0), 1) end as neto_linea,
         d.neto_desbordado
  from cab c join det d on d.orden = c.orden
  union all
  select c.*, null, false, null, c.neto * c.signo, false
  from cab c
  where not exists (select 1 from det d where d.orden = c.orden)
), cli as materialized (
  select cl.codigo, cl.razon_social, cl.cuit, g.descripcion as grupo, g.tipo
  from core.clientes cl left join core.grupos_cliente g on g.codigo = cl.grupo_codigo
), art as materialized (
  select codigo, descripcion from core.articulos
), ven as materialized (
  select codigo, nombre from core.vendedores
), prd as materialized (
  select codigo_tekno, familia, unidades_por, kg_por, estado from core.productos
)
select
  l.fecha,
  date_trunc('month', l.fecha)::date                          as mes,
  extract(year from l.fecha)::int                             as anio,
  case when l.es_fiscal then 'Factura' else 'Presupuesto' end as canal_fiscal,
  l.tipo_comprobante,
  lpad(l.punto_venta::text, 4, '0') || '-' || lpad(l.numero::text, 8, '0') as comprobante,
  l.cliente_codigo,
  coalesce(cli.razon_social, 'Cliente ' || l.cliente_codigo, 'Sin cliente') as cliente,
  cli.cuit                                                    as cliente_cuit,
  coalesce(cli.grupo, 'SIN GRUPO')                            as grupo_cliente,
  coalesce(cli.tipo, 'SIN GRUPO')                             as tipo_cliente,
  coalesce(ven.nombre, l.vendedor_codigo)                     as vendedor,
  coalesce(l.articulo_codigo, 'SIN DETALLE')                  as producto_codigo,
  case when l.articulo_codigo is null then 'SIN DETALLE'
       when l.es_despacho then 'DESPACHO (flete)'
       else coalesce(art.descripcion, l.articulo_codigo) end  as producto,
  l.es_despacho                                               as es_flete,
  l.cantidad_linea                                            as cantidad,
  l.neto_linea                                                as neto,
  l.neto_desbordado,
  case when l.articulo_codigo is null then 'SIN DETALLE'
       when l.es_despacho then 'DESPACHO'
       else coalesce(prd.familia, 'SIN CLASIFICAR') end      as familia,
  l.cantidad_linea * prd.unidades_por                         as unidades,
  round(l.cantidad_linea * prd.kg_por, 3)                     as kilos,
  prd.estado                                                  as producto_estado
from lineas l
left join cli on cli.codigo = l.cliente_codigo
left join art on art.codigo = l.articulo_codigo
left join ven on ven.codigo = l.vendedor_codigo
left join prd on prd.codigo_tekno = lpad(l.articulo_codigo, 7, '0');

-- La vista materializada y la vista de Looker se recrean para tomar las columnas nuevas.
drop view if exists public.reporte_ventas;
drop materialized view if exists rpt.ventas_analisis;
create materialized view rpt.ventas_analisis as select * from calc.ventas_analisis with no data;
create index if not exists ventas_analisis_mes_idx     on rpt.ventas_analisis (mes);
create index if not exists ventas_analisis_cliente_idx on rpt.ventas_analisis (cliente_codigo);

create or replace view public.reporte_ventas as select * from rpt.ventas_analisis;
revoke all on public.reporte_ventas from anon, authenticated, public;
grant select on rpt.ventas_analisis, public.reporte_ventas to looker_lectura;

-- Vista para Looker con el maestro (consulta de productos, equivalencias y kilos).
create or replace view public.reporte_productos as
select codigo, familia, producto, nivel, envase, unidades_por, gramos_unidad, kg_por, estado, en_indice
from core.productos;
revoke all on public.reporte_productos from anon, authenticated, public;
grant select on public.reporte_productos to looker_lectura;

select calc.refrescar_rpt();

-- Control: kilos por familia en el ultimo mes cerrado y lineas sin clasificar.
select familia,
       round(sum(kilos), 0)    as kilos,
       round(sum(unidades), 0) as unidades,
       round(sum(neto), 2)     as neto
from rpt.ventas_analisis
where mes = date_trunc('month', current_date - interval '1 month')::date
group by familia
order by kilos desc nulls last;
