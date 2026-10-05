-- SCARA · teste do esquema
-- Roda dentro de uma transação e desfaz tudo no fim. Pode ser repetido no mesmo banco.
-- Uso: psql -v ON_ERROR_STOP=1 -d scara -f server/db/teste.sql

\set QUIET on
begin;
set search_path = scara, public;
set timezone = 'America/Fortaleza';

-- Auxiliares ----------------------------------------------------------------

create function pg_temp.ev(p_boot int, p_seq int, p_tipo text, p_massa int, p_em timestamptz,
                           p_estavel boolean default true, p_ref_seq int default null)
returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'boot', p_boot, 'seq', p_seq, 'tipo', p_tipo, 'massa_g', p_massa,
    'estavel', p_estavel, 'desvio_g', 10, 'uptime_ms', p_seq * 1000,
    'epoch_ms', (extract(epoch from p_em) * 1000)::bigint,
    'ref_boot', case when p_ref_seq is not null then p_boot end, 'ref_seq', p_ref_seq))
$$;

create function pg_temp.producao(p_brinco text, p_data date, p_turno turno) returns int
language sql as $$
  select producao_g from v_ordenha
   where brinco = p_brinco and data = p_data and turno = p_turno and anulada_em is null
$$;

-- Cadastro --------------------------------------------------------------------

insert into fazenda (id, nome, municipio) values
  ('00000000-0000-0000-0000-000000000001', 'Fazenda piloto', 'Morada Nova');
insert into posto (id, fazenda_id, numero, tara_referencia_g) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 1, 12000);
insert into animal (id, fazenda_id, brinco, ordem_entrada) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001', 'V01', 1),
  ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-000000000001', 'V02', 2),
  ('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-000000000001', 'V03', 3),
  ('00000000-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-000000000001', 'V04', 4);
insert into lactacao (animal_id, data_parto) values
  ('00000000-0000-0000-0000-0000000000b1', '2026-07-01'),
  ('00000000-0000-0000-0000-0000000000b2', '2026-08-01'),
  ('00000000-0000-0000-0000-0000000000b3', '2026-06-01');
-- V04 seca: sem lactação aberta. V03 ausente na manhã do dia 5.
insert into ausencia values ('00000000-0000-0000-0000-0000000000b3', '2026-10-05', 'manha', 'casco');
insert into medida_racao values ('00000000-0000-0000-0000-000000000001', '2026-09-01', 1250);
insert into racao_programada values ('00000000-0000-0000-0000-0000000000b1', 'manha', '2026-09-01', 2);
insert into racao_programada values ('00000000-0000-0000-0000-0000000000b2', 'manha', '2026-09-01', 3);

select nova_chave_posto('00000000-0000-0000-0000-0000000000a1') as chave \gset

-- 1. Ordenha simples com reenvio ----------------------------------------------

select selecionar_animal('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');

select ingerir(:'chave', 1, 999999, jsonb_build_array(
  pg_temp.ev(1, 1, 'balde_colocado', 12000, '2026-10-05 05:30'),
  pg_temp.ev(1, 2, 'inicio',         12050, '2026-10-05 05:31'),
  pg_temp.ev(1, 3, 'fim',            20050, '2026-10-05 05:39'))) as ack \gset

do $$ begin
  assert (select count(*) from evento_posto) = 3, 'devia ter 3 eventos';
end $$;

-- Reenvio do mesmo lote não duplica e confirma o último.
select ingerir(:'chave', 1, 999999, jsonb_build_array(
  pg_temp.ev(1, 1, 'balde_colocado', 12000, '2026-10-05 05:30'),
  pg_temp.ev(1, 2, 'inicio',         12050, '2026-10-05 05:31'),
  pg_temp.ev(1, 3, 'fim',            20050, '2026-10-05 05:39'))) as ack2 \gset

do $$ begin
  assert (select count(*) from evento_posto) = 3, 'reenvio duplicou eventos';
  assert pg_temp.producao('V01', '2026-10-05', 'manha') = 8000, 'V01 devia ter 8000 g';
  assert not exists (select 1 from selecao_posto), 'seleção devia ser consumida no fim';
end $$;
select :'ack2'::jsonb = '{"boot": 1, "seq": 3}'::jsonb as ack_ok \gset
\if :ack_ok
\else
  \echo 'FALHA: ack do reenvio errado'
  select 1/0;
\endif

-- 2. Esvaziamento no meio da vaca ---------------------------------------------

select selecionar_animal('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2');

-- Lote fora de ordem: o servidor ordena por boot e seq.
select ingerir(:'chave', 1, 999999, jsonb_build_array(
  pg_temp.ev(1, 5, 'fim',            26050, '2026-10-05 05:48'),
  pg_temp.ev(1, 4, 'inicio',         20050, '2026-10-05 05:40'),
  pg_temp.ev(1, 6, 'balde_retirado', 26050, '2026-10-05 05:49'),
  pg_temp.ev(1, 7, 'balde_colocado', 12010, '2026-10-05 05:52'),
  pg_temp.ev(1, 8, 'inicio',         12010, '2026-10-05 05:53'),
  pg_temp.ev(1, 9, 'fim',            14010, '2026-10-05 05:56')));

do $$ begin
  assert (select count(*) from v_ordenha where animal_id is null and anulada_em is null) = 1,
    'segunda parcial devia ficar sem animal';
  assert exists (select 1 from v_pendencia where motivo = 'sem animal'), 'pendência sem animal ausente';
end $$;

-- Operador associa a parcial pendente à V02: as parciais são mescladas.
select associar_animal(id, '00000000-0000-0000-0000-0000000000b2')
  from ordenha where animal_id is null and anulada_em is null;

do $$ begin
  assert pg_temp.producao('V02', '2026-10-05', 'manha') = 8000, 'V02 devia somar 6000 + 2000';
  assert (select parciais from v_ordenha where brinco = 'V02') = 2, 'V02 devia ter 2 parciais';
  assert (select valida from v_ordenha where brinco = 'V02'), 'V02 devia ser válida';
end $$;

-- 3. Uso da sessão: V01 e V02 esperadas, V03 ausente, V04 seca ----------------

do $$ begin
  assert (select esperadas from v_uso_sessao where data = '2026-10-05' and turno = 'manha') = 2, 'esperadas devia ser 2';
  assert (select taxa_pct from v_uso_sessao where data = '2026-10-05' and turno = 'manha') = 100, 'taxa devia ser 100';
end $$;

-- 4. Ração: V01 sem lançamento fica estimada; V02 lançada ---------------------

insert into racao_fornecida (sessao_id, animal_id, medidas)
select sessao_id, animal_id, 2.5 from v_ordenha where brinco = 'V02';

do $$ begin
  assert (select estimado and fornecido_g = 2500 from v_racao where brinco = 'V01'), 'ração V01 errada';
  assert (select not estimado and fornecido_g = 3125 from v_racao where brinco = 'V02'), 'ração V02 errada';
end $$;

-- 5. Anulação de início -------------------------------------------------------

select ingerir(:'chave', 1, 999999, jsonb_build_array(
  pg_temp.ev(1, 10, 'inicio', 14010, '2026-10-05 06:00'),
  pg_temp.ev(1, 11, 'anula',  null,  '2026-10-05 06:00', true, 10)));

do $$ begin
  assert not exists (select 1 from parcial where evento_fim is null and not anulada), 'parcial devia estar anulada';
  assert not exists (select 1 from v_pendencia where motivo = 'sem animal'), 'ordenha vazia devia ser anulada';
end $$;

-- 6. Evento fora de sequência é gravado com erro, e o lote é confirmado -------

select ingerir(:'chave', 1, 999999, jsonb_build_array(
  pg_temp.ev(1, 12, 'fim', 14010, '2026-10-05 06:05'))) as ack3 \gset

do $$ begin
  assert (select erro from evento_posto where seq = 12) = 'fim sem início', 'erro de sequência ausente';
end $$;
select :'ack3'::jsonb = '{"boot": 1, "seq": 12}'::jsonb as ack_ok \gset
\if :ack_ok
\else
  \echo 'FALHA: evento com erro não foi confirmado'
  select 1/0;
\endif

-- 7. Seleção com parcial já aberta associa na hora, e hora estimada ------------

select ingerir(:'chave', 2, 50000, jsonb_build_array(
  jsonb_build_object('boot', 2, 'seq', 13, 'tipo', 'inicio', 'massa_g', 14010,
                     'estavel', true, 'uptime_ms', 20000)));
select selecionar_animal('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b3');

do $$ begin
  assert (select hora_estimada from evento_posto where seq = 13), 'hora devia ser estimada';
  assert (select ocorrido_em between now() - interval '31 s' and now() - interval '29 s'
            from evento_posto where seq = 13), 'hora estimada fora do esperado';
  assert exists (select 1 from v_cartao_posto where brinco = 'V03' and ordenhando), 'cartão devia mostrar V03';
end $$;

-- Fecha a parcial da V03 com produção zero: fica registrada, mas inválida.
select ingerir(:'chave', 2, 60000, jsonb_build_array(
  jsonb_build_object('boot', 2, 'seq', 14, 'tipo', 'fim', 'massa_g', 14010,
                     'estavel', true, 'uptime_ms', 59000)));

do $$ begin
  assert exists (select 1 from v_pendencia where motivo = 'produção fora da faixa'), 'V03 devia ficar pendente';
end $$;

-- 8. Chave inválida -----------------------------------------------------------

do $$ begin
  begin
    perform ingerir('x' || repeat('0', 47), 1, 0, '[]'::jsonb);
    assert false, 'chave inválida aceita';
  exception when sqlstate '28000' then null;
  end;
end $$;

-- 9. Eventos são imutáveis ----------------------------------------------------

do $$ begin
  begin
    update evento_posto set massa_g = 0 where seq = 2;
    assert false, 'evento alterado';
  exception when raise_exception then null;
  end;
  begin
    delete from evento_posto where seq = 2;
    assert false, 'evento apagado';
  exception when raise_exception then null;
  end;
end $$;

-- 10. Alerta de queda ---------------------------------------------------------

select set_config('teste.chave', :'chave', true);
-- V01 com 8 kg por 7 manhãs, depois duas manhãs a 6 kg.

do $$
declare
  chave text := current_setting('teste.chave');
  dia   date;
  seq_  int := 100;
  massa int;
begin
  for i in 1..9 loop
    dia := date '2026-10-06' + i;
    massa := case when i >= 8 then 6000 else 8000 end;
    perform selecionar_animal('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
    perform ingerir(chave, 3, 0, jsonb_build_array(
      pg_temp.ev(3, seq_,     'balde_retirado', 0,             (dia + time '05:00')::timestamptz),
      pg_temp.ev(3, seq_ + 1, 'balde_colocado', 12000,         (dia + time '05:01')::timestamptz),
      pg_temp.ev(3, seq_ + 2, 'inicio',         12000,         (dia + time '05:02')::timestamptz),
      pg_temp.ev(3, seq_ + 3, 'fim',            12000 + massa, (dia + time '05:10')::timestamptz)));
    seq_ := seq_ + 4;
  end loop;
end $$;

do $$ begin
  -- Última: 6000 sobre média 7714 (já inclui a primeira queda) = 78%. Anterior: 6000 sobre 8000 = 75%.
  assert exists (select 1 from v_alerta_queda where brinco = 'V01'
                   and pct_da_media = 78 and pct_da_media_anterior = 75),
    'alerta de queda da V01 ausente';
end $$;

-- 11. Login do painel ---------------------------------------------------------

insert into config_segura values ('jwt_segredo', repeat('s', 40));
select definir_pin('00000000-0000-0000-0000-000000000001', '482913');

do $$
declare
  tok text;
begin
  tok := entrar('482913');
  assert tok ~ '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$', 'token com formato errado';
  assert entrar('000000') is null, 'PIN errado aceito';
  for i in 1..5 loop perform entrar('111111'); end loop;
  assert entrar('482913') is null, 'bloqueio por tentativas não funcionou';
end $$;

-- 12. Permissões --------------------------------------------------------------

set local role scara_operador;
select count(*) as cartoes from v_cartao_posto \gset
do $$ begin
  begin
    perform pin_hash from fazenda;
    assert false, 'operador leu pin_hash';
  exception when insufficient_privilege then null;
  end;
  begin
    perform chave_hash from posto;
    assert false, 'operador leu chave_hash';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into evento_posto (posto_id, boot, seq, tipo, uptime_ms, ocorrido_em, hora_estimada)
    values ('00000000-0000-0000-0000-0000000000a1', 9, 9, 'inicio', 0, now(), true);
    assert false, 'operador gravou evento direto';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

set local role scara_anon;
do $$ begin
  begin
    perform 1 from animal;
    assert false, 'anônimo leu animal';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from v_ordenha;
    assert false, 'anônimo leu ordenhas';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- 13. Conciliação ---------------------------------------------------------------

insert into coleta_tanque (fazenda_id, coletado_em, volume_l, origem) values
  ('00000000-0000-0000-0000-000000000001', '2026-10-04 18:00', 100, 'ticket'),
  ('00000000-0000-0000-0000-000000000001', '2026-10-05 18:00', 15.5, 'ticket');

do $$ begin
  -- V01 8 kg + V02 8 kg + V03 em aberto = 16 kg = 15,5 L a 1,032 kg/L
  assert (select postos_l from v_conciliacao) = 15.5, 'conciliação errada';
end $$;

-- 14. Mudança de manejo escalonada por lote -------------------------------------
-- Lote A recebe ração nova em 23/10. V01 (lote A) sobe 1 kg; V02 (controle) fica igual.
-- Clima igual nas duas janelas. Adaptação 0 e janela de 3 dias para o teste ser curto.

insert into lote (id, fazenda_id, nome) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'A');
insert into lote_animal values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000c1', '2026-10-01', null);

insert into mudanca_manejo (id, fazenda_id, tipo, escopo, lote_id, inicio, adaptacao_dias, janela_dias, titulo, descricao, hipotese, custo_dia)
values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000001', 'racao', 'lote',
        '00000000-0000-0000-0000-0000000000c1', '2026-10-23', 0, 3, 'Concentrado 20% PB no lote A',
        'Troca do concentrado de 16% para 20% de proteína', '+0,5 kg por vaca em 3 dias', 10.00);

do $$
declare
  chave text := current_setting('teste.chave');
  dia   date;
  seq_  int := 200;
  v1    int;
begin
  for i in 0..5 loop
    dia := date '2026-10-20' + i;
    v1 := case when dia >= '2026-10-23' then 8000 else 7000 end;
    insert into ambiente values ('00000000-0000-0000-0000-000000000001', dia + time '14:00', 'manual', 32.0, 50.0, null);
    -- V01, posto 1
    perform selecionar_animal('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
    perform ingerir(chave, 4, 0, jsonb_build_array(
      pg_temp.ev(4, seq_,     'balde_retirado', 0,          (dia + time '05:00')::timestamptz),
      pg_temp.ev(4, seq_ + 1, 'balde_colocado', 12000,      (dia + time '05:01')::timestamptz),
      pg_temp.ev(4, seq_ + 2, 'inicio',         12000,      (dia + time '05:02')::timestamptz),
      pg_temp.ev(4, seq_ + 3, 'fim',            12000 + v1, (dia + time '05:10')::timestamptz)));
    -- V02, mesmo posto, logo depois
    perform selecionar_animal('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2');
    perform ingerir(chave, 4, 0, jsonb_build_array(
      pg_temp.ev(4, seq_ + 4, 'inicio', 12000 + v1,        (dia + time '05:12')::timestamptz),
      pg_temp.ev(4, seq_ + 5, 'fim',    12000 + v1 + 7000, (dia + time '05:20')::timestamptz)));
    seq_ := seq_ + 6;
  end loop;
end $$;

do $$
declare r record;
begin
  select * into r from v_efeito_mudanca where id = '00000000-0000-0000-0000-0000000000d1';
  assert r.desenho = 'escalonado por lote', 'desenho errado';
  assert r.n_tratadas = 1 and r.n_controle = 1, format('contagem errada: %s tratadas, %s controle', r.n_tratadas, r.n_controle);
  assert r.efeito_g_vaca_dia = 1000, format('efeito devia ser 1000, veio %s', r.efeito_g_vaca_dia);
  assert r.itu_base = r.itu_efeito, 'ITU devia ser igual nas duas janelas';
  assert r.veredicto in ('aguardando a janela', 'vacas insuficientes'), format('veredicto inesperado: %s', r.veredicto);
  assert (select itu(32.0, 50.0)) between 80 and 82, 'ITU de 32 °C e 50% devia ficar perto de 81';
  assert not exists (select 1 from v_mudanca_sobreposta), 'não devia haver sobreposição';
end $$;

\echo 'teste.sql: todos os cenários passaram'
rollback;
