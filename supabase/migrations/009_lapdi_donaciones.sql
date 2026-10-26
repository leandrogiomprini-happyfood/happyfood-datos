-- 009_lapdi_donaciones.sql
-- LAPDI (00407) son donaciones: confirmado por Cuci el 26/10/2026. Se excluye de ventas igual que 00405.
-- Se puede volver a ejecutar sin riesgo.

insert into core.clientes_internos (codigo, motivo) values
  ('00407', 'LAPDI: donaciones')
on conflict (codigo) do nothing;

select calc.refrescar_rpt();

select codigo, motivo from core.clientes_internos order by codigo;
