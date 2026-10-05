-- SCARA · dados de demonstração
-- Uma fazenda, três vacas, um lote, uma mudança de manejo e seis dias de ordenha.
-- Usado pelos testes de exportação e para demonstrar o painel. Não usar em produção.
-- Aplicar depois de schema.sql e exportacao.sql.

begin;
set search_path = scara, public;

insert into fazenda (id, nome, municipio, codigo) values
  ('00000000-0000-0000-0000-00000000f001', 'Fazenda Demonstração', 'Morada Nova', 'DEMO');
insert into posto (id, fazenda_id, numero, tara_referencia_g) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000f001', 1, 12000);
insert into animal (id, fazenda_id, brinco, nome, raca, nascimento, ordem_entrada) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000f001', '101', 'Mimosa',  'Girolando', '2021-03-10', 1),
  ('00000000-0000-0000-0000-00000000b002', '00000000-0000-0000-0000-00000000f001', '102', 'Estrela', 'Girolando', '2020-07-22', 2),
  ('00000000-0000-0000-0000-00000000b003', '00000000-0000-0000-0000-00000000f001', '103', 'Pintada', 'Guzolando', '2019-11-05', 3);
insert into lactacao (animal_id, data_parto, data_secagem) values
  ('00000000-0000-0000-0000-00000000b001', '2026-07-01', null),
  ('00000000-0000-0000-0000-00000000b002', '2026-08-01', null),
  ('00000000-0000-0000-0000-00000000b003', '2025-05-10', '2026-03-01'),
  ('00000000-0000-0000-0000-00000000b003', '2026-06-01', null);
insert into medida_racao values ('00000000-0000-0000-0000-00000000f001', '2026-09-01', 1250);
insert into racao_programada values
  ('00000000-0000-0000-0000-00000000b001', 'manha', '2026-09-01', 2),
  ('00000000-0000-0000-0000-00000000b002', 'manha', '2026-09-01', 3),
  ('00000000-0000-0000-0000-00000000b003', 'manha', '2026-09-01', 2);
insert into lote (id, fazenda_id, nome, descricao) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000f001', 'A', 'Lote de alta produção');
insert into lote_animal values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000c001', '2026-09-01', null),
  ('00000000-0000-0000-0000-00000000b003', '00000000-0000-0000-0000-00000000c001', '2026-09-01', '2026-09-20');

select set_config('demo.chave', nova_chave_posto('00000000-0000-0000-0000-00000000a001'), false);

do $$
declare
  chave text := current_setting('demo.chave');
  dia   date;
  seq_  int := 0;
  massa int[] := array[7000, 8500, 6000];
  vacas uuid[] := array['00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000b002',
                        '00000000-0000-0000-0000-00000000b003'];
  nivel int;
  hora  time;
begin
  for i in 0..5 loop
    dia := date '2026-09-25' + i;
    insert into ambiente values ('00000000-0000-0000-0000-00000000f001', dia + time '14:00', 'manual', 31.0 + i, 55.0, null);
    foreach hora in array array[time '05:00', time '15:00'] loop
      nivel := 12000;
      perform ingerir(chave, 1, 0, jsonb_build_array(
        jsonb_build_object('boot', 1, 'seq', seq_,     'tipo', 'balde_retirado', 'massa_g', 0,     'estavel', true, 'uptime_ms', 0,
                           'epoch_ms', (extract(epoch from (dia + hora) at time zone 'America/Fortaleza') * 1000)::bigint),
        jsonb_build_object('boot', 1, 'seq', seq_ + 1, 'tipo', 'balde_colocado', 'massa_g', nivel, 'estavel', true, 'uptime_ms', 0,
                           'epoch_ms', (extract(epoch from (dia + hora + interval '1 min') at time zone 'America/Fortaleza') * 1000)::bigint)));
      seq_ := seq_ + 2;
      for v in 1..3 loop
        perform selecionar_animal('00000000-0000-0000-0000-00000000a001', vacas[v]);
        perform ingerir(chave, 1, 0, jsonb_build_array(
          jsonb_build_object('boot', 1, 'seq', seq_, 'tipo', 'inicio', 'massa_g', nivel, 'estavel', true, 'uptime_ms', 0,
                             'epoch_ms', (extract(epoch from (dia + hora + make_interval(mins => 2 + v * 10)) at time zone 'America/Fortaleza') * 1000)::bigint),
          jsonb_build_object('boot', 1, 'seq', seq_ + 1, 'tipo', 'fim', 'massa_g', nivel + massa[v] / 2, 'estavel', true, 'uptime_ms', 0,
                             'epoch_ms', (extract(epoch from (dia + hora + make_interval(mins => 10 + v * 10)) at time zone 'America/Fortaleza') * 1000)::bigint)));
        nivel := nivel + massa[v] / 2;
        seq_ := seq_ + 2;
      end loop;
    end loop;
  end loop;
end $$;

-- Ração conferida para uma vaca num dia; as demais ficam estimadas.
insert into racao_fornecida (sessao_id, animal_id, medidas)
select s.id, '00000000-0000-0000-0000-00000000b002', 2.5 from sessao s
 where s.fazenda_id = '00000000-0000-0000-0000-00000000f001' and s.data = '2026-09-26' and s.turno = 'manha';

insert into mudanca_manejo (fazenda_id, tipo, escopo, lote_id, inicio, adaptacao_dias, janela_dias, titulo, descricao, hipotese)
values ('00000000-0000-0000-0000-00000000f001', 'racao', 'lote', '00000000-0000-0000-0000-00000000c001', '2026-09-28', 0, 3,
        'Concentrado 20% PB no lote A', 'Troca de 16% para 20% de proteína bruta', '+0,5 kg por vaca');

commit;
