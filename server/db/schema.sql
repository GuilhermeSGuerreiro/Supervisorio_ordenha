-- SCARA · esquema do servidor local
-- PostgreSQL 16. Aplicar com: psql -v ON_ERROR_STOP=1 -d scara -f server/db/schema.sql
-- Decisões que guiam este arquivo: docs/06-decisoes.md (D1 a D9).

begin;

create extension if not exists pgcrypto;

create schema if not exists scara;
set search_path = scara, public;

-- Nada nasce executável por PUBLIC neste esquema. Cada função recebe grant explícito no fim.
alter default privileges in schema scara revoke execute on functions from public;

-- Papéis usados pelo PostgREST. Senha do papel de login fica fora do repositório.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'scara_anon') then
    create role scara_anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'scara_operador') then
    create role scara_operador nologin;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------

create type turno as enum ('manha', 'tarde', 'noite');
create type destino_leite as enum ('tanque', 'descarte', 'bezerro', 'casa');
create type tipo_evento as enum ('inicio', 'fim', 'balde_colocado', 'balde_retirado', 'anula');
create type origem_coleta as enum ('ticket', 'regua');

-- ---------------------------------------------------------------------------
-- Cadastro
-- ---------------------------------------------------------------------------

create table fazenda (
  id               uuid primary key default gen_random_uuid(),
  nome             text not null,
  municipio        text,
  fuso             text not null default 'America/Fortaleza',
  densidade_kg_l   numeric(5,4) not null default 1.032 check (densidade_kg_l between 1.000 and 1.100),
  hora_corte_tarde time not null default '12:00',
  hora_corte_noite time,                       -- nulo: fazenda com duas ordenhas
  pin_hash         text,                       -- bcrypt do PIN do painel
  criado_em        timestamptz not null default now(),
  check (hora_corte_noite is null or hora_corte_noite > hora_corte_tarde)
);

create table animal (
  id                  uuid primary key default gen_random_uuid(),
  fazenda_id          uuid not null references fazenda,
  brinco              text not null,
  nome                text,
  raca                text,
  nascimento          date,
  ordenha_com_bezerro boolean not null default false,
  ordem_entrada       int,
  baixa_em            date,
  motivo_baixa        text check (motivo_baixa in ('venda', 'morte', 'descarte', 'outro')),
  criado_em           timestamptz not null default now(),
  unique (fazenda_id, brinco),
  check ((baixa_em is null) = (motivo_baixa is null))
);

-- Situação do animal é derivada: lactação aberta = em lactação, sem lactação aberta = seca.
create table lactacao (
  id           uuid primary key default gen_random_uuid(),
  animal_id    uuid not null references animal,
  data_parto   date not null,
  data_secagem date,
  unique (animal_id, data_parto),
  check (data_secagem is null or data_secagem >= data_parto)
);
create unique index lactacao_uma_aberta on lactacao (animal_id) where data_secagem is null;

create table ausencia (
  animal_id uuid not null references animal,
  data      date not null,
  turno     turno not null,
  motivo    text not null,
  primary key (animal_id, data, turno)
);

create table posto (
  id                uuid primary key default gen_random_uuid(),
  fazenda_id        uuid not null references fazenda,
  numero            smallint not null check (numero > 0),
  nome              text,
  chave_hash        bytea unique,                -- sha256 da chave; nulo = posto bloqueado
  limite_balde_g    int not null default 57000 check (limite_balde_g > 0),
  tara_referencia_g int check (tara_referencia_g > 0),
  criado_em         timestamptz not null default now(),
  unique (fazenda_id, numero)
);

-- ---------------------------------------------------------------------------
-- Eventos do posto (imutáveis, D8)
-- ---------------------------------------------------------------------------

create table evento_posto (
  id            bigint generated always as identity primary key,
  posto_id      uuid not null references posto,
  boot          int not null check (boot >= 0),
  seq           int not null check (seq >= 0),
  tipo          tipo_evento not null,
  massa_g       int,
  bruto         int,
  estavel       boolean not null default true,
  desvio_g      int,
  ref_boot      int,
  ref_seq       int,
  uptime_ms     bigint not null check (uptime_ms >= 0),
  ocorrido_em   timestamptz not null,
  hora_estimada boolean not null,
  recebido_em   timestamptz not null default now(),
  erro          text,                            -- evento fora de sequência (D4)
  anulado_por   bigint references evento_posto,
  unique (posto_id, boot, seq),
  check ((tipo = 'anula') = (ref_seq is not null and ref_boot is not null))
);

create function _evento_imutavel() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'evento_posto é imutável: use anulação';
  end if;
  if (new.posto_id, new.boot, new.seq, new.tipo, new.massa_g, new.bruto, new.estavel,
      new.desvio_g, new.ref_boot, new.ref_seq, new.uptime_ms, new.ocorrido_em,
      new.hora_estimada, new.recebido_em)
     is distinct from
     (old.posto_id, old.boot, old.seq, old.tipo, old.massa_g, old.bruto, old.estavel,
      old.desvio_g, old.ref_boot, old.ref_seq, old.uptime_ms, old.ocorrido_em,
      old.hora_estimada, old.recebido_em) then
    raise exception 'evento_posto é imutável: só erro e anulado_por podem mudar';
  end if;
  return new;
end $$;

create trigger evento_imutavel before update or delete on evento_posto
  for each row execute function _evento_imutavel();

create table posto_status (
  posto_id      uuid primary key references posto,
  massa_g       int,
  estavel       boolean,
  estado        text,
  rssi          int,
  fila          int,
  boot          int,
  versao        text,
  atualizado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Estrutura derivada dos eventos
-- ---------------------------------------------------------------------------

create table balde_ciclo (
  id               bigint generated always as identity primary key,
  posto_id         uuid not null references posto,
  evento_colocado  bigint not null unique references evento_posto,
  evento_retirado  bigint unique references evento_posto,
  tara_g           int,
  anulado          boolean not null default false
);
create unique index balde_ciclo_um_aberto on balde_ciclo (posto_id)
  where evento_retirado is null and not anulado;

create table sessao (
  id         uuid primary key default gen_random_uuid(),
  fazenda_id uuid not null references fazenda,
  data       date not null,
  turno      turno not null,
  unique (fazenda_id, data, turno)
);

create table ordenha (
  id             uuid primary key default gen_random_uuid(),
  sessao_id      uuid not null references sessao,
  animal_id      uuid references animal,          -- nulo: pendente de associação
  destino        destino_leite not null default 'tanque',
  observacao     text,
  anulada_em     timestamptz,
  anulada_motivo text,
  criado_em      timestamptz not null default now(),
  check ((anulada_em is null) = (anulada_motivo is null))
);
create unique index ordenha_uma_por_animal on ordenha (sessao_id, animal_id)
  where animal_id is not null and anulada_em is null;

create table parcial (
  id             bigint generated always as identity primary key,
  posto_id       uuid not null references posto,
  ordenha_id     uuid not null references ordenha,
  balde_ciclo_id bigint references balde_ciclo,
  evento_inicio  bigint not null unique references evento_posto,
  evento_fim     bigint unique references evento_posto,
  massa_inicio_g int,
  massa_fim_g    int,
  estavel        boolean not null,
  inconsistente  text,
  anulada        boolean not null default false,
  producao_g     int generated always as (massa_fim_g - massa_inicio_g) stored
);
create unique index parcial_uma_aberta on parcial (posto_id)
  where evento_fim is null and not anulada;
create index parcial_ordenha on parcial (ordenha_id);

-- Vaca escolhida no painel para o próximo início do posto. Consumida no fim (docs/02-operacao.md).
create table selecao_posto (
  posto_id    uuid primary key references posto,
  animal_id   uuid not null references animal,
  definido_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Ração, ocorrências, intervenções, tanque
-- ---------------------------------------------------------------------------

create table medida_racao (
  fazenda_id   uuid not null references fazenda,
  calibrada_em date not null,
  massa_g      int not null check (massa_g > 0),
  primary key (fazenda_id, calibrada_em)
);

create table racao_programada (
  animal_id      uuid not null references animal,
  turno          turno not null,
  vigente_desde  date not null,
  medidas        numeric(5,2) not null check (medidas >= 0),
  primary key (animal_id, turno, vigente_desde)
);

create table racao_fornecida (
  sessao_id     uuid not null references sessao,
  animal_id     uuid not null references animal,
  medidas       numeric(5,2) not null check (medidas >= 0),
  sobra_medidas numeric(5,2) check (sobra_medidas >= 0),
  registrado_em timestamptz not null default now(),
  primary key (sessao_id, animal_id)
);

create table ocorrencia (
  id             uuid primary key default gen_random_uuid(),
  fazenda_id     uuid not null references fazenda,
  animal_id      uuid references animal,
  posto_id       uuid references posto,
  sessao_id      uuid references sessao,
  tipo           text not null check (tipo in ('saude', 'manejo', 'equipamento', 'ajuda', 'fazenda', 'outro')),
  descricao      text not null,
  ocorrido_em    timestamptz not null default now(),
  registrado_por text
);

create table intervencao (
  id             uuid primary key default gen_random_uuid(),
  animal_id      uuid not null references animal,
  data           date not null,
  tipo           text not null check (tipo in ('medicamento', 'racao', 'exame', 'secagem', 'outro')),
  descricao      text not null,
  carencia_ate   date,
  alerta_origem  text,
  acompanhamento text,
  resultado      text,
  registrado_em  timestamptz not null default now(),
  check (carencia_ate is null or carencia_ate >= data)
);

create table coleta_tanque (
  id          uuid primary key default gen_random_uuid(),
  fazenda_id  uuid not null references fazenda,
  coletado_em timestamptz not null,
  volume_l    numeric(8,1) not null check (volume_l > 0),
  origem      origem_coleta not null,
  observacao  text,
  unique (fazenda_id, coletado_em)
);

-- ---------------------------------------------------------------------------
-- Segurança do painel
-- ---------------------------------------------------------------------------

create table config_segura (
  chave text primary key,
  valor text not null
);
revoke all on config_segura from public;

create table tentativa_login (
  em timestamptz not null default now(),
  ok boolean not null
);
revoke all on tentativa_login from public;

-- ---------------------------------------------------------------------------
-- Funções auxiliares
-- ---------------------------------------------------------------------------

create function turno_de(p_fazenda uuid, p_em timestamptz) returns turno
language sql stable as $$
  select case
           when (p_em at time zone f.fuso)::time < f.hora_corte_tarde then 'manha'::turno
           when f.hora_corte_noite is not null
                and (p_em at time zone f.fuso)::time >= f.hora_corte_noite then 'noite'::turno
           else 'tarde'::turno
         end
    from fazenda f where f.id = p_fazenda
$$;

create function data_de(p_fazenda uuid, p_em timestamptz) returns date
language sql stable as $$
  select (p_em at time zone f.fuso)::date from fazenda f where f.id = p_fazenda
$$;

create function sessao_de(p_fazenda uuid, p_em timestamptz) returns uuid
language plpgsql as $$
declare
  d   date  := data_de(p_fazenda, p_em);
  t   turno := turno_de(p_fazenda, p_em);
  id_ uuid;
begin
  if d is null then
    raise exception 'fazenda inexistente';
  end if;
  insert into sessao (fazenda_id, data, turno) values (p_fazenda, d, t)
    on conflict (fazenda_id, data, turno) do nothing
    returning id into id_;
  if id_ is null then
    select id into strict id_ from sessao where fazenda_id = p_fazenda and data = d and turno = t;
  end if;
  return id_;
end $$;

create function destino_padrao(p_animal uuid, p_data date) returns destino_leite
language sql stable as $$
  select case when exists (
    select 1 from intervencao
     where animal_id = p_animal and carencia_ate is not null
       and p_data between data and carencia_ate
  ) then 'descarte'::destino_leite else 'tanque'::destino_leite end
$$;

-- Associa uma ordenha a um animal. Se o animal já tem ordenha na sessão, mescla as parciais nela.
create function associar_animal(p_ordenha uuid, p_animal uuid) returns uuid
language plpgsql security definer set search_path = scara, public, extensions, pg_temp as $$
declare
  o       ordenha;
  alvo_id uuid;
  dia     date;
begin
  select * into strict o from ordenha where id = p_ordenha for update;
  if o.anulada_em is not null then
    raise exception 'ordenha anulada';
  end if;
  if o.animal_id is not distinct from p_animal then
    return o.id;
  end if;
  if not exists (
    select 1 from animal a join sessao s on s.fazenda_id = a.fazenda_id
     where a.id = p_animal and s.id = o.sessao_id
  ) then
    raise exception 'animal de outra fazenda';
  end if;

  select id into alvo_id from ordenha
   where sessao_id = o.sessao_id and animal_id = p_animal and anulada_em is null and id <> o.id;

  if alvo_id is not null then
    update parcial set ordenha_id = alvo_id where ordenha_id = o.id;
    update ordenha set anulada_em = now(), anulada_motivo = 'mesclada em ' || alvo_id where id = o.id;
    return alvo_id;
  end if;

  select data into dia from sessao where id = o.sessao_id;
  update ordenha set animal_id = p_animal, destino = destino_padrao(p_animal, dia) where id = o.id;
  return o.id;
end $$;

-- Escolhe a vaca do posto. Com parcial aberta, associa direto. Sem parcial aberta, vale para o próximo início.
create function selecionar_animal(p_posto uuid, p_animal uuid) returns uuid
language plpgsql security definer set search_path = scara, public, extensions, pg_temp as $$
declare
  ord uuid;
begin
  select ordenha_id into ord from parcial
   where posto_id = p_posto and evento_fim is null and not anulada;
  if ord is not null then
    return associar_animal(ord, p_animal);
  end if;
  insert into selecao_posto (posto_id, animal_id) values (p_posto, p_animal)
    on conflict (posto_id) do update set animal_id = excluded.animal_id, definido_em = now();
  return null;
end $$;

create function anular_ordenha(p_ordenha uuid, p_motivo text) returns void
language plpgsql security definer set search_path = scara, public, extensions, pg_temp as $$
begin
  if coalesce(trim(p_motivo), '') = '' then
    raise exception 'motivo obrigatório';
  end if;
  update ordenha set anulada_em = now(), anulada_motivo = p_motivo
   where id = p_ordenha and anulada_em is null;
end $$;

-- Aplica um evento recém-gravado. Erros de sequência são devolvidos como texto, nunca como exceção (D4).
create function _processar_evento(e evento_posto) returns text
language plpgsql as $$
declare
  faz     uuid;
  ciclo   balde_ciclo;
  par     parcial;
  ses     uuid;
  ord     uuid;
  sel     uuid;
  alvo    evento_posto;
begin
  select fazenda_id into strict faz from posto where id = e.posto_id;
  select * into ciclo from balde_ciclo
   where posto_id = e.posto_id and evento_retirado is null and not anulado;
  select * into par from parcial
   where posto_id = e.posto_id and evento_fim is null and not anulada;

  case e.tipo
  when 'inicio' then
    if par.id is not null then
      return 'início com parcial aberta';
    end if;
    ses := sessao_de(faz, e.ocorrido_em);
    select animal_id into sel from selecao_posto where posto_id = e.posto_id;
    if sel is not null then
      select id into ord from ordenha
       where sessao_id = ses and animal_id = sel and anulada_em is null;
      if ord is null then
        insert into ordenha (sessao_id, animal_id, destino)
        values (ses, sel, destino_padrao(sel, (select data from sessao where id = ses)))
        returning id into ord;
      end if;
    else
      insert into ordenha (sessao_id) values (ses) returning id into ord;
    end if;
    insert into parcial (posto_id, ordenha_id, balde_ciclo_id, evento_inicio, massa_inicio_g, estavel, inconsistente)
    values (e.posto_id, ord, ciclo.id, e.id, e.massa_g, e.estavel and e.massa_g is not null,
            case when ciclo.id is null then 'início sem balde colocado' end);
    return case when ciclo.id is null then 'início sem balde colocado' end;

  when 'fim' then
    if par.id is null then
      return 'fim sem início';
    end if;
    update parcial set
      evento_fim    = e.id,
      massa_fim_g   = e.massa_g,
      estavel       = par.estavel and e.estavel and e.massa_g is not null,
      inconsistente = coalesce(par.inconsistente,
                        case when par.balde_ciclo_id is distinct from ciclo.id
                             then 'troca de balde durante a parcial' end)
     where id = par.id;
    delete from selecao_posto where posto_id = e.posto_id;
    return null;

  when 'balde_colocado' then
    if ciclo.id is not null then
      return 'balde colocado sem retirada anterior';
    end if;
    insert into balde_ciclo (posto_id, evento_colocado, tara_g) values (e.posto_id, e.id, e.massa_g);
    return null;

  when 'balde_retirado' then
    if ciclo.id is null then
      return 'balde retirado sem balde colocado';
    end if;
    update balde_ciclo set evento_retirado = e.id where id = ciclo.id;
    return case when par.id is not null then 'balde retirado com parcial aberta' end;

  when 'anula' then
    select * into alvo from evento_posto
     where posto_id = e.posto_id and boot = e.ref_boot and seq = e.ref_seq;
    if alvo.id is null then
      return 'anulação de evento inexistente';
    end if;
    if alvo.anulado_por is not null then
      return 'evento já anulado';
    end if;
    update evento_posto set anulado_por = e.id where id = alvo.id;
    case alvo.tipo
      when 'inicio' then
        update parcial set anulada = true where evento_inicio = alvo.id returning ordenha_id into ord;
        update ordenha set anulada_em = now(), anulada_motivo = 'início anulado no posto'
         where id = ord and anulada_em is null
           and not exists (select 1 from parcial where ordenha_id = ord and not anulada);
      when 'fim' then
        if par.id is not null then
          return 'anulação de fim com outra parcial aberta';
        end if;
        update parcial set evento_fim = null, massa_fim_g = null where evento_fim = alvo.id;
      when 'balde_colocado' then
        update balde_ciclo set anulado = true where evento_colocado = alvo.id;
      when 'balde_retirado' then
        if ciclo.id is not null then
          return 'anulação de retirada com outro balde colocado';
        end if;
        update balde_ciclo set evento_retirado = null where evento_retirado = alvo.id;
      else
        return 'anulação de anulação não é suportada';
    end case;
    return null;
  end case;
end $$;

-- ---------------------------------------------------------------------------
-- API do posto (D2, D3, D4)
-- ---------------------------------------------------------------------------

create function _posto_por_chave(p_chave text) returns uuid
language plpgsql stable as $$
declare
  id_ uuid;
begin
  if p_chave is null or length(p_chave) < 32 then
    raise exception 'chave inválida' using errcode = '28000';
  end if;
  select id into id_ from posto where chave_hash = digest(p_chave, 'sha256');
  if id_ is null then
    raise exception 'chave inválida' using errcode = '28000';
  end if;
  return id_;
end $$;

-- Recebe um lote de eventos em ordem. Devolve o último (boot, seq) confirmado.
create function ingerir(p_chave text, p_boot int, p_uptime_ms bigint, p_eventos jsonb) returns jsonb
language plpgsql security definer set search_path = scara, public, extensions, pg_temp as $$
declare
  posto_  uuid := _posto_por_chave(p_chave);
  ev      jsonb;
  epoch_  bigint;
  quando  timestamptz;
  estim   boolean;
  novo    evento_posto;
  erro_   text;
  ult_b   int;
  ult_s   int;
begin
  if jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) > 200 then
    raise exception 'lote inválido' using errcode = '22023';
  end if;

  for ev in
    select x from jsonb_array_elements(p_eventos) x
     order by (x->>'boot')::int, (x->>'seq')::int
  loop
    epoch_ := (ev->>'epoch_ms')::bigint;
    if epoch_ is not null and epoch_ > 1700000000000 then
      quando := to_timestamp(epoch_ / 1000.0);
      estim  := false;
    elsif (ev->>'boot')::int = p_boot and p_uptime_ms >= (ev->>'uptime_ms')::bigint then
      quando := now() - make_interval(secs => (p_uptime_ms - (ev->>'uptime_ms')::bigint) / 1000.0);
      estim  := true;
    else
      quando := now();
      estim  := true;
    end if;

    insert into evento_posto (posto_id, boot, seq, tipo, massa_g, bruto, estavel, desvio_g,
                              ref_boot, ref_seq, uptime_ms, ocorrido_em, hora_estimada)
    values (posto_, (ev->>'boot')::int, (ev->>'seq')::int, (ev->>'tipo')::tipo_evento,
            (ev->>'massa_g')::int, (ev->>'bruto')::int, coalesce((ev->>'estavel')::boolean, false),
            (ev->>'desvio_g')::int, (ev->>'ref_boot')::int, (ev->>'ref_seq')::int,
            (ev->>'uptime_ms')::bigint, quando, estim)
    on conflict (posto_id, boot, seq) do nothing
    returning * into novo;

    if novo.id is not null then
      begin
        erro_ := _processar_evento(novo);
      exception when others then
        erro_ := 'falha no processamento: ' || sqlerrm;
      end;
      if erro_ is not null then
        update evento_posto set erro = erro_ where id = novo.id;
      end if;
      novo := null;
    end if;

    ult_b := (ev->>'boot')::int;
    ult_s := (ev->>'seq')::int;
  end loop;

  return jsonb_build_object('boot', ult_b, 'seq', ult_s);
end $$;

-- Devolve os maiores boot e seq já recebidos. O posto usa isso para se corrigir se a flash for apagada.
create function status_posto(p_chave text, p_status jsonb) returns jsonb
language plpgsql security definer set search_path = scara, public, extensions, pg_temp as $$
declare
  posto_ uuid := _posto_por_chave(p_chave);
begin
  insert into posto_status (posto_id, massa_g, estavel, estado, rssi, fila, boot, versao, atualizado_em)
  values (posto_, (p_status->>'massa_g')::int, (p_status->>'estavel')::boolean,
          left(p_status->>'estado', 20), (p_status->>'rssi')::int, (p_status->>'fila')::int,
          (p_status->>'boot')::int, left(p_status->>'versao', 20), now())
  on conflict (posto_id) do update set
    massa_g = excluded.massa_g, estavel = excluded.estavel, estado = excluded.estado,
    rssi = excluded.rssi, fila = excluded.fila, boot = excluded.boot,
    versao = excluded.versao, atualizado_em = excluded.atualizado_em;
  return (select jsonb_build_object('boot_max', coalesce(max(boot), 0), 'seq_max', coalesce(max(seq), 0))
            from evento_posto where posto_id = posto_);
end $$;

-- Gera uma chave nova para o posto. A chave em texto só aparece nesta resposta (D9).
create function nova_chave_posto(p_posto uuid) returns text
language plpgsql security definer set search_path = scara, public, extensions, pg_temp as $$
declare
  chave text := encode(gen_random_bytes(24), 'hex');
begin
  update posto set chave_hash = digest(chave, 'sha256') where id = p_posto;
  if not found then
    raise exception 'posto inexistente';
  end if;
  return chave;
end $$;

-- ---------------------------------------------------------------------------
-- Login do painel: PIN para JWT assinado com o segredo do PostgREST
-- ---------------------------------------------------------------------------

create function _b64url(b bytea) returns text language sql immutable as $$
  select translate(rtrim(replace(encode(b, 'base64'), E'\n', ''), '='), '+/', '-_')
$$;

create function definir_pin(p_fazenda uuid, p_pin text) returns void
language plpgsql security definer set search_path = scara, public, extensions, pg_temp as $$
begin
  if p_pin !~ '^[0-9]{6,}$' then
    raise exception 'PIN precisa ter pelo menos 6 dígitos';
  end if;
  update fazenda set pin_hash = crypt(p_pin, gen_salt('bf', 10)) where id = p_fazenda;
end $$;

create function entrar(p_pin text) returns text
language plpgsql security definer set search_path = scara, public, extensions, pg_temp as $$
declare
  faz      uuid;
  segredo  text;
  dias     int;
  cab      text;
  corpo    text;
begin
  if (select count(*) from tentativa_login where not ok and em > now() - interval '5 minutes') >= 5 then
    return null;
  end if;

  select id into faz from fazenda
   where pin_hash is not null and pin_hash = crypt(p_pin, pin_hash)
   limit 1;
  insert into tentativa_login (ok) values (faz is not null);
  delete from tentativa_login where em < now() - interval '1 day';
  if faz is null then
    return null;
  end if;

  select valor into segredo from config_segura where chave = 'jwt_segredo';
  if segredo is null or length(segredo) < 32 then
    raise exception 'jwt_segredo ausente ou curto em config_segura';
  end if;
  dias := coalesce((select valor::int from config_segura where chave = 'jwt_dias'), 30);

  cab   := _b64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'utf8'));
  corpo := _b64url(convert_to(jsonb_build_object(
             'role', 'scara_operador',
             'fazenda_id', faz,
             'exp', extract(epoch from now() + make_interval(days => dias))::bigint
           )::text, 'utf8'));
  return cab || '.' || corpo || '.' ||
         _b64url(hmac(convert_to(cab || '.' || corpo, 'utf8'), convert_to(segredo, 'utf8'), 'sha256'));
end $$;

-- ---------------------------------------------------------------------------
-- Visões para o painel e relatórios
-- ---------------------------------------------------------------------------

create view v_ordenha as
select
  o.id,
  o.sessao_id,
  s.fazenda_id,
  s.data,
  s.turno,
  o.animal_id,
  a.brinco,
  o.destino,
  o.anulada_em,
  count(p.id)                                   as parciais,
  coalesce(sum(p.producao_g), 0)::int           as producao_g,
  coalesce(bool_and(p.evento_fim is not null), false) as fechada,
  coalesce(bool_and(p.estavel), false)          as estavel,
  coalesce(bool_or(p.inconsistente is not null), false) as inconsistente,
  min(ei.ocorrido_em)                           as inicio_em,
  max(ef.ocorrido_em)                           as fim_em,
  (o.anulada_em is null
   and o.animal_id is not null
   and count(p.id) > 0
   and coalesce(bool_and(p.evento_fim is not null), false)
   and coalesce(bool_and(p.estavel), false)
   and not coalesce(bool_or(p.inconsistente is not null), false)
   and coalesce(sum(p.producao_g), 0) between 300 and 40000) as valida
from ordenha o
join sessao s on s.id = o.sessao_id
left join animal a on a.id = o.animal_id
left join parcial p on p.ordenha_id = o.id and not p.anulada
left join evento_posto ei on ei.id = p.evento_inicio
left join evento_posto ef on ef.id = p.evento_fim
group by o.id, s.id, a.id;

create view v_animal as
select
  a.*,
  l.data_parto,
  case
    when a.baixa_em is not null then 'baixa'
    when l.id is not null then 'lactacao'
    else 'seca'
  end as situacao,
  case when l.id is not null then current_date - l.data_parto end as del
from animal a
left join lactacao l on l.animal_id = a.id and l.data_secagem is null;

-- Ordenhas esperadas e válidas por sessão (meta de 95%, docs/04-validacao.md).
create view v_uso_sessao as
with esperadas as (
  select s.id as sessao_id, a.id as animal_id
    from sessao s
    join animal a on a.fazenda_id = s.fazenda_id
    join lactacao l on l.animal_id = a.id
                   and l.data_parto <= s.data
                   and (l.data_secagem is null or l.data_secagem > s.data)
   where (a.baixa_em is null or a.baixa_em > s.data)
     and not exists (select 1 from ausencia au
                      where au.animal_id = a.id and au.data = s.data and au.turno = s.turno)
)
select
  s.id as sessao_id, s.fazenda_id, s.data, s.turno,
  count(e.animal_id)                                  as esperadas,
  count(e.animal_id) filter (where vo.valida)         as validas,
  round(100.0 * count(e.animal_id) filter (where vo.valida) / nullif(count(e.animal_id), 0), 1) as taxa_pct
from sessao s
left join esperadas e on e.sessao_id = s.id
left join v_ordenha vo on vo.sessao_id = s.id and vo.animal_id = e.animal_id and vo.valida
group by s.id;

-- Queda de produção: duas ordenhas válidas seguidas abaixo de 80% da média do mesmo turno nos 7 dias anteriores.
create view v_alerta_queda as
with base as (
  select vo.*,
         (select avg(b.producao_g) from v_ordenha b
           where b.animal_id = vo.animal_id and b.turno = vo.turno and b.valida
             and b.data between vo.data - 7 and vo.data - 1
          having count(*) >= 3) as media_turno_g
    from v_ordenha vo
   where vo.valida
),
razao as (
  select base.*,
         producao_g / nullif(media_turno_g, 0) as razao,
         row_number() over (partition by animal_id order by data desc, turno desc) as ordem
    from base
)
select r1.animal_id, r1.brinco, r1.data, r1.turno, r1.producao_g,
       round(r1.media_turno_g)::int as media_turno_g,
       round(r1.razao * 100, 0) as pct_da_media,
       round(r2.razao * 100, 0) as pct_da_media_anterior
  from razao r1
  join razao r2 on r2.animal_id = r1.animal_id and r2.ordem = 2
 where r1.ordem = 1 and r1.razao < 0.8 and r2.razao < 0.8;

create view v_racao as
select
  vo.sessao_id, vo.fazenda_id, vo.data, vo.turno, vo.animal_id, vo.brinco,
  rp.medidas                                            as programadas,
  coalesce(rf.medidas, rp.medidas)                      as fornecidas,
  rf.sobra_medidas,
  rf.medidas is null                                    as estimado,
  mr.massa_g                                            as massa_medida_g,
  round(coalesce(rf.medidas, rp.medidas) * mr.massa_g)::int as fornecido_g
from v_ordenha vo
left join lateral (
  select medidas from racao_programada
   where animal_id = vo.animal_id and turno = vo.turno and vigente_desde <= vo.data
   order by vigente_desde desc limit 1
) rp on true
left join racao_fornecida rf on rf.sessao_id = vo.sessao_id and rf.animal_id = vo.animal_id
left join lateral (
  select massa_g from medida_racao
   where fazenda_id = vo.fazenda_id and calibrada_em <= vo.data
   order by calibrada_em desc limit 1
) mr on true
where vo.valida;

-- Conciliação: leite com destino tanque entre duas coletas, comparado com o volume coletado.
create view v_conciliacao as
with periodos as (
  select c.*, lag(c.coletado_em) over (partition by c.fazenda_id order by c.coletado_em) as desde
    from coleta_tanque c
)
select
  p.id, p.fazenda_id, p.desde, p.coletado_em, p.origem, p.volume_l,
  round(coalesce(sum(vo.producao_g), 0) / 1000.0 / f.densidade_kg_l, 1) as postos_l,
  round(100.0 * (coalesce(sum(vo.producao_g), 0) / 1000.0 / f.densidade_kg_l - p.volume_l) / p.volume_l, 1) as diferenca_pct
from periodos p
join fazenda f on f.id = p.fazenda_id
left join v_ordenha vo on vo.fazenda_id = p.fazenda_id and vo.valida and vo.destino = 'tanque'
                      and vo.fim_em <= p.coletado_em
                      and (p.desde is null or vo.fim_em > p.desde)
where p.desde is not null
group by p.id, p.fazenda_id, p.desde, p.coletado_em, p.origem, p.volume_l, f.densidade_kg_l;

-- Cartão do posto na tela principal.
create view v_cartao_posto as
select
  po.id as posto_id, po.fazenda_id, po.numero, po.nome,
  st.massa_g, st.estavel, st.estado, st.rssi, st.fila, st.atualizado_em,
  coalesce(st.atualizado_em > now() - interval '20 seconds', false) as online,
  bc.tara_g,
  st.massa_g - bc.tara_g                                    as nivel_g,
  po.limite_balde_g - (st.massa_g - bc.tara_g)              as capacidade_restante_g,
  coalesce(ao.id, asel.id)                                  as animal_id,
  coalesce(ao.brinco, asel.brinco)                          as brinco,
  pa.id is not null                                         as ordenhando,
  ei.ocorrido_em                                            as inicio_em,
  pa.massa_inicio_g,
  (select round(avg(b.producao_g))::int from v_ordenha b
    where b.animal_id = coalesce(ao.id, asel.id) and b.valida
      and b.data >= current_date - 7
      and b.turno = turno_de(po.fazenda_id, now())) as esperado_g
from posto po
left join posto_status st on st.posto_id = po.id
left join balde_ciclo bc on bc.posto_id = po.id and bc.evento_retirado is null and not bc.anulado
left join parcial pa on pa.posto_id = po.id and pa.evento_fim is null and not pa.anulada
left join evento_posto ei on ei.id = pa.evento_inicio
left join ordenha o on o.id = pa.ordenha_id
left join animal ao on ao.id = o.animal_id
left join selecao_posto sp on sp.posto_id = po.id
left join animal asel on asel.id = sp.animal_id;

-- Tudo o que precisa de atenção do operador.
create view v_pendencia as
select 'ordenha' as origem, vo.id::text as ref, vo.data, vo.turno,
       case
         when vo.animal_id is null then 'sem animal'
         when not vo.fechada then 'sem fim'
         when vo.inconsistente then 'inconsistente'
         when not vo.estavel then 'leitura instável'
         else 'produção fora da faixa'
       end as motivo
  from v_ordenha vo
 where vo.anulada_em is null and not vo.valida
union all
select 'evento', e.id::text, (e.ocorrido_em at time zone f.fuso)::date, null, e.erro
  from evento_posto e
  join posto p on p.id = e.posto_id
  join fazenda f on f.id = p.fazenda_id
 where e.erro is not null
union all
select 'balde', bc.id::text, (e.ocorrido_em at time zone f.fuso)::date, null,
       'tara difere ' || abs(bc.tara_g - p.tara_referencia_g) || ' g da referência'
  from balde_ciclo bc
  join posto p on p.id = bc.posto_id
  join fazenda f on f.id = p.fazenda_id
  join evento_posto e on e.id = bc.evento_colocado
 where not bc.anulado and p.tara_referencia_g is not null
   and abs(bc.tara_g - p.tara_referencia_g) > 300;

-- ---------------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------------

grant usage on schema scara to scara_anon, scara_operador;

-- Posto e login: chamados sem token.
grant execute on function ingerir(text, int, bigint, jsonb) to scara_anon;
grant execute on function status_posto(text, jsonb) to scara_anon;
grant execute on function entrar(text) to scara_anon;

-- Painel com token.
grant select on v_ordenha, v_animal, v_uso_sessao, v_alerta_queda, v_racao,
                v_conciliacao, v_cartao_posto, v_pendencia to scara_operador;
grant select on animal, lactacao, ausencia, sessao, ordenha, parcial,
                balde_ciclo, posto_status, selecao_posto, medida_racao, racao_programada,
                racao_fornecida, ocorrencia, intervencao, coleta_tanque, evento_posto to scara_operador;
grant select (id, fazenda_id, numero, nome, limite_balde_g, tara_referencia_g, criado_em)
  on posto to scara_operador;
grant select (id, nome, municipio, fuso, densidade_kg_l, hora_corte_tarde, hora_corte_noite, criado_em)
  on fazenda to scara_operador;
grant insert, update on animal, lactacao, ausencia, medida_racao, racao_programada,
                        racao_fornecida, ocorrencia, intervencao, coleta_tanque to scara_operador;
grant update (destino, observacao) on ordenha to scara_operador;
grant update (nome, limite_balde_g, tara_referencia_g) on posto to scara_operador;
grant execute on function selecionar_animal(uuid, uuid), associar_animal(uuid, uuid),
                          anular_ordenha(uuid, text), nova_chave_posto(uuid),
                          definir_pin(uuid, text) to scara_operador;
-- Funções chamadas pelas visões.
grant execute on function turno_de(uuid, timestamptz), data_de(uuid, timestamptz),
                          destino_padrao(uuid, date) to scara_operador;

commit;
