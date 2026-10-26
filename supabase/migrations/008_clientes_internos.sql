-- 008_clientes_internos.sql
-- Clientes que son movimientos internos de HappyFood (mismo CUIT 30-71529103-3): no son ventas.
-- Confirmado por Cuci el 26/10/2026 para 00039; 00405 y 00406 comparten el CUIT de HappyFood.
-- Se excluyen de core.ventas_vigentes, y por lo tanto de todos los reportes de ventas y cobranzas.
-- Para sumar o quitar uno: insert/delete en core.clientes_internos y luego select calc.refrescar_rpt();

create table if not exists core.clientes_internos (
  codigo  text primary key,
  motivo  text not null
);
alter table core.clientes_internos enable row level security;

insert into core.clientes_internos (codigo, motivo) values
  ('00039', 'HAPPY FOOD SA: movimientos internos'),
  ('00405', 'DONACIONES (CUIT de HappyFood)'),
  ('00406', 'MUESTRAS COMERCIALES (CUIT de HappyFood)')
on conflict (codigo) do nothing;

create or replace view core.ventas_vigentes as
select *
from core.ventas v
where not v.eliminado_origen
  and not v.anulado
  and not exists (select 1 from core.clientes_internos i where i.codigo = v.cliente_codigo);

select calc.refrescar_rpt();
