-- SCARA · simulação para o vídeo de demonstração
-- 12 vacas, 3 postos, ordem fixa de entrada, 21 dias, duas ordenhas por dia.
-- Todos os eventos passam por scara.ingerir, como se viessem dos postos pela coleta.
-- Calibração com a observação de campo de outubro de 2026: máquina ~5 min por vaca, ~10 min de troca por rodada.
-- Cenário: ração nova no lote A a partir do dia 11; onda de calor nos dias 14 a 18 atinge todas as vacas.
-- Aplicar depois de schema.sql e exportacao.sql, num banco vazio.

begin;
set search_path = scara, public;
select setseed(0.4242);

create function pg_temp.gauss(media double precision, dp double precision) returns double precision
language sql volatile as $$
  select media + dp * sqrt(-2 * ln(greatest(random(), 1e-12))) * cos(2 * pi() * random())
$$;

create function pg_temp.ms(dia date, hora interval) returns bigint language sql immutable as $$
  select (extract(epoch from (dia + hora) at time zone 'America/Fortaleza') * 1000)::bigint
$$;

insert into fazenda (id, nome, municipio, codigo) values
  ('00000000-0000-0000-0000-0000000d0001', 'Fazenda Demonstração', 'Morada Nova', 'DEMO');

insert into posto (id, fazenda_id, numero, tara_referencia_g)
select ('00000000-0000-0000-0000-0000000da00' || n)::uuid, '00000000-0000-0000-0000-0000000d0001', n, 12000
  from generate_series(1, 3) n;

-- 12 vacas; ordem de entrada 1..12; posto habitual em rodízio 1, 2, 3.
insert into animal (id, fazenda_id, brinco, raca, ordem_entrada, posto_habitual)
select ('00000000-0000-0000-0000-0000000db' || lpad(n::text, 3, '0'))::uuid,
       '00000000-0000-0000-0000-0000000d0001', (100 + n)::text, 'Girolando', n, ((n - 1) % 3) + 1
  from generate_series(1, 12) n;

insert into lactacao (animal_id, data_parto)
select id, date '2026-04-01' + ((ordem_entrada * 11) % 130)
  from animal where fazenda_id = '00000000-0000-0000-0000-0000000d0001';

-- Lote A: seis vacas escolhidas para ter produção média parecida com a do controle, duas por posto.
-- É o que docs/08-mensuracao-manejo.md pede: lotes comparáveis antes da mudança.
insert into lote (id, fazenda_id, nome, descricao) values
  ('00000000-0000-0000-0000-0000000dc001', '00000000-0000-0000-0000-0000000d0001', 'A', 'Lote que recebe a ração nova');
insert into lote_animal (animal_id, lote_id, desde)
select id, '00000000-0000-0000-0000-0000000dc001', '2026-08-25'
  from animal where fazenda_id = '00000000-0000-0000-0000-0000000d0001' and ordem_entrada in (1, 3, 5, 8, 10, 12);

insert into mudanca_manejo (id, fazenda_id, tipo, escopo, lote_id, inicio, adaptacao_dias, janela_dias,
                            titulo, descricao, hipotese)
values ('00000000-0000-0000-0000-0000000dd001', '00000000-0000-0000-0000-0000000d0001', 'racao', 'lote',
        '00000000-0000-0000-0000-0000000dc001', '2026-09-11', 3, 7,
        'Concentrado com mais proteína no lote A', 'Troca do concentrado de 16% para 20% de proteína bruta',
        '+0,5 kg por vaca por dia');

-- Clima: leituras a cada 3 horas; onda de calor nos dias 14 a 18.
insert into ambiente (fazenda_id, medido_em, origem, temperatura_c, umidade_pct, local)
select '00000000-0000-0000-0000-0000000d0001',
       (d + make_interval(hours => h)) at time zone 'America/Fortaleza', 'inmet',
       round((27 + 5.5 * sin(pi() * (h - 6) / 12.0) * (h between 6 and 18)::int
              + case when d between '2026-09-14' and '2026-09-18' then 4 else 0 end
              + pg_temp.gauss(0, 0.4))::numeric, 1),
       round((72 - 25 * sin(pi() * (h - 6) / 12.0) * (h between 6 and 18)::int + pg_temp.gauss(0, 2))::numeric, 1),
       'Morada Nova A332'
  from (select g::date as d from generate_series(date '2026-09-01', date '2026-09-21', interval '1 day') g) dias,
       generate_series(0, 21, 3) h;

do $$
declare
  chaves  text[];
  base    double precision[] := array[11.5, 9.8, 8.6, 12.4, 7.2, 10.1, 6.5, 9.0, 8.1, 10.8, 7.7, 9.4];
  dia     date;
  d       int;
  sess    int;
  hora0   interval;
  frac    double precision;
  p       int;
  seqs    int[] := array[0, 0, 0];
  eventos jsonb;
  nivel   int;
  t       double precision;   -- minutos desde o início da sessão
  dur     double precision;
  kg      double precision;
  prod    int;
  vaca    int;
  r       int;
  tara    int;
begin
  select array_agg(nova_chave_posto(id) order by numero) into chaves
    from posto where fazenda_id = '00000000-0000-0000-0000-0000000d0001';

  for d in 1..21 loop
    dia := date '2026-09-01' + (d - 1);
    for sess in 1..2 loop
      hora0 := case sess when 1 then interval '5 hours' else interval '15 hours' end;
      frac  := case sess when 1 then 0.55 else 0.45 end;
      for p in 1..3 loop
        eventos := '[]'::jsonb;
        tara := 12000 + round(pg_temp.gauss(0, 25))::int;
        seqs[p] := seqs[p] + 1;
        eventos := eventos || jsonb_build_object('boot', 1, 'seq', seqs[p], 'tipo', 'balde_colocado', 'massa_g', tara,
                     'estavel', true, 'uptime_ms', 0, 'epoch_ms', pg_temp.ms(dia, hora0 - interval '3 min'));
        nivel := tara;
        t := (p - 1) * 1.0;   -- o operador liga os postos um após o outro
        for r in 0..3 loop
          vaca := r * 3 + p;  -- ordem de entrada da vaca neste posto e rodada
          kg := base[vaca] * (1 - 0.0025 * (d - 1))
                * case when d between 14 and 18 then 0.92 else 1 end
                + case when vaca in (1, 3, 5, 8, 10, 12) and d = 11 then 0.3
                       when vaca in (1, 3, 5, 8, 10, 12) and d >= 12 then 0.8 else 0 end;
          prod := greatest(300, round(kg * frac * (1 + pg_temp.gauss(0, 0.04)) * 1000))::int;
          dur := greatest(3.0, pg_temp.gauss(5.0, 0.7));
          seqs[p] := seqs[p] + 1;
          eventos := eventos || jsonb_build_object('boot', 1, 'seq', seqs[p], 'tipo', 'inicio', 'massa_g', nivel,
                       'estavel', true, 'uptime_ms', 0, 'epoch_ms', pg_temp.ms(dia, hora0 + make_interval(secs => t * 60)));
          t := t + dur;
          nivel := nivel + prod;
          seqs[p] := seqs[p] + 1;
          eventos := eventos || jsonb_build_object('boot', 1, 'seq', seqs[p], 'tipo', 'fim', 'massa_g', nivel,
                       'estavel', true, 'uptime_ms', 0, 'epoch_ms', pg_temp.ms(dia, hora0 + make_interval(secs => t * 60)));
          t := t + greatest(6.0, pg_temp.gauss(10.0, 1.5));  -- troca: saída, tinas, entrada, preparo
        end loop;
        seqs[p] := seqs[p] + 1;
        eventos := eventos || jsonb_build_object('boot', 1, 'seq', seqs[p], 'tipo', 'balde_retirado', 'massa_g', nivel,
                     'estavel', true, 'uptime_ms', 0, 'epoch_ms', pg_temp.ms(dia, hora0 + make_interval(secs => t * 60)));
        perform ingerir(chaves[p], 1, 0, eventos);
      end loop;
    end loop;
  end loop;
end $$;

commit;
