-- 024_estado_ak_minusculas.sql
-- Correccion de la 023 (29/10/2026): en "Control Stock en Dias" tres marcas estan escritas en minuscula
-- ("inactivo": 204 Oleomargarina, 201 Esencia Naranja Harmony, 141 Harina de Soja) y la 023 solo
-- reconocia "Inactivo". Ahora se compara sin importar mayusculas ni espacios.
-- Ademas, Cuci confirma como inactivos los flexibles de Brasil (196, 197, 198): pasan de "por pedido"
-- a "inactivo" (no se muestran).
-- Se puede volver a ejecutar sin riesgo.

create or replace view core.insumos_estado_planilla as
select distinct on (hojas.num(f.valores -> 0)::int)
       hojas.num(f.valores -> 0)::int  as insumo_codigo,
       hojas.txt(f.valores -> 1)       as insumo_planilla,
       initcap(btrim(hojas.txt(f.valores -> 36))) as estado_ak,
       f.fuente
from hojas.filas f
where f.fuente in ('envases_flx', 'insumos_activos')
  and hojas.num(f.valores -> 0) is not null
  and lower(btrim(hojas.txt(f.valores -> 36))) in ('activo', 'inactivo')
order by hojas.num(f.valores -> 0)::int, (lower(btrim(hojas.txt(f.valores -> 36))) = 'activo') desc;

update core.insumos_config set modo = 'inactivo', motivo = 'Flexible Brasil: inactivo (Cuci, 29/10/2026)', actualizado = now()
where insumo_codigo in (196, 197, 198);

-- Control: los 13 inactivos de la columna AK y como quedan.
select p.insumo_codigo, p.insumo_planilla, p.estado_ak,
       coalesce(m.modo_efectivo, 'no esta en el conteo') as como_queda,
       case when m.revisar_estado then 'se muestra: se sigue consumiendo' end as nota
from core.insumos_estado_planilla p
left join calc.insumos_modo m on m.insumo_codigo = p.insumo_codigo
where p.estado_ak = 'Inactivo'
order by p.insumo_codigo;
