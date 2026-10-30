-- 027_fuente_costos.sql
-- Nueva pestaña a leer (pedido de Cuci, 30/10/2026): planilla "movivent", hoja "kgxArtiActual",
-- con los kilos por articulo (columna D) y el ultimo costo por articulo (columna AS; la fecha del costo
-- esta en la fila 1). Sirve para costo de lo vendido y contribucion marginal en el reporte de ventas.
-- Esta migracion solo la suma a la lectura automatica y muestra las primeras filas para armar la 028.
-- Requisito: compartir la planilla con la cuenta de servicio (Lector).
-- Se puede volver a ejecutar sin riesgo.

insert into hojas.fuentes (fuente, planilla_id, hoja, tipo, descripcion, cada_minutos) values
  ('costos_articulos', '1uV9xB-D6wMthZvj1AQZEJ9smeiClAebWlpzCoLD-KSQ', 'kgxArtiActual', 'sheet',
   'Movivent: kilos y ultimo costo por articulo', 60)
on conflict (fuente) do update set planilla_id = excluded.planilla_id, hoja = excluded.hoja,
  descripcion = excluded.descripcion, cada_minutos = excluded.cada_minutos;

select hojas.disparar();
