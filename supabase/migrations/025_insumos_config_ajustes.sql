-- 025_insumos_config_ajustes.sql
-- Decisiones de Cuci (29/10/2026) sobre los casos de la 024:
--   224 y 225: son las cajas terciarias impresas en uso. La columna AK de la planilla las marca
--              Inactivo con otro nombre ("Caja Madre 3D"): se fuerzan como activas.
--   141 Harina de Soja: es para fason, a demanda. Igual que Chocosoja: "por pedido" (se ve, sin alertas).
-- Se puede volver a ejecutar sin riesgo.

insert into core.insumos_config (insumo_codigo, modo, motivo) values
  (224, 'regular',    'Caja terciaria impresa en uso; en la columna AK figura como Caja Madre 3D galletas Inactivo'),
  (225, 'regular',    'Caja terciaria impresa en uso; en la columna AK figura como Caja Madre 3D alfajores Inactivo'),
  (141, 'por_pedido', 'Harina de Soja: fason a demanda')
on conflict (insumo_codigo) do update set modo = excluded.modo, motivo = excluded.motivo, actualizado = now();

select calc.refrescar_insumos();

-- Control: configuracion cargada a mano.
select c.insumo_codigo, coalesce(i.nombre, '-') as insumo, c.modo, c.motivo
from core.insumos_config c
left join core.insumos i on i.codigo = c.insumo_codigo
order by c.modo, c.insumo_codigo;
