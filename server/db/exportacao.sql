-- SCARA · exportação de dados
-- ICAR ADE 1.5 (JSON) e controle leiteiro em CSV para GisLeite, IDEAGRI e similares.
-- Aplicar depois de schema.sql: psql -v ON_ERROR_STOP=1 -d scara -f server/db/exportacao.sql
-- Padrão: https://github.com/adewg/ICAR (Apache 2.0). Decisão D13 em docs/06-decisoes.md.

begin;
set search_path = scara, public;

-- ---------------------------------------------------------------------------
-- Identificadores e auxiliares
-- ---------------------------------------------------------------------------

-- Fonte dos dados, no formato DNS reverso pedido pelo padrão.
create function _ade_fonte() returns text language sql immutable as $$ select 'br.scara' $$;

-- Data e hora em UTC, RFC 3339 com Z.
create function _ade_ts(t timestamptz) returns text language sql immutable as $$
  select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
$$;

-- Data local (meia-noite no fuso da fazenda) convertida para UTC.
create function _ade_data(d date, p_fuso text) returns text language sql stable as $$
  select _ade_ts((d::timestamp) at time zone p_fuso)
$$;

-- Meia-noite local com o deslocamento do fuso da fazenda, ex.: 2026-09-25T00:00:00-03:00.
-- Usado onde o padrão pede a data local de um turno mas tipa o campo como data-hora.
create function _ade_data_local(d date, p_fuso text) returns text language plpgsql stable as $$
declare
  desloc interval := d::timestamp - ((d::timestamp) at time zone p_fuso) at time zone 'UTC';
  sinal  text := case when desloc < interval '0' then '-' else '+' end;
begin
  return to_char(d, 'YYYY-MM-DD') || 'T00:00:00' || sinal
         || to_char(abs(extract(epoch from desloc))::int / 3600, 'FM00') || ':'
         || to_char((abs(extract(epoch from desloc))::int % 3600) / 60, 'FM00');
end $$;

create function _ade_meta(p_source_id text, p_modified timestamptz, p_created timestamptz) returns jsonb
language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'source', _ade_fonte(),
    'sourceId', p_source_id,
    'modified', _ade_ts(coalesce(p_modified, p_created)),
    'created', _ade_ts(p_created),
    'isDeleted', false))
$$;

-- Local: esquema oficial se cadastrado, senão o esquema próprio com o código da fazenda.
create function _ade_local(f fazenda) returns jsonb language sql immutable as $$
  select case
    when f.ade_location_scheme is not null
      then jsonb_build_object('scheme', f.ade_location_scheme, 'id', f.ade_location_id)
    else jsonb_build_object('scheme', 'br.scara.fazenda', 'id', coalesce(f.codigo, f.id::text))
  end
$$;

-- Animal: sem esquema nacional obrigatório para leite, o padrão ICAR recomenda o composto fazenda.animal.
create function _ade_animal(a animal, f fazenda) returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'scheme', 'composite.withinherdid',
    'id', coalesce(f.codigo, left(f.id::text, 8)) || '.' || a.brinco)
$$;

create function _ade_colecao(p_membros jsonb, p_total bigint, p_pagina int, p_tamanho int) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'view', jsonb_build_object(
      'totalItems', p_total,
      'totalPages', greatest(1, ceil(p_total::numeric / greatest(p_tamanho, 1)))::int,
      'pageSize', p_tamanho,
      'currentPage', p_pagina),
    'member', coalesce(p_membros, '[]'::jsonb))
$$;

-- ---------------------------------------------------------------------------
-- Animais · icarAnimalCoreResource · GET /locations/{scheme}/{id}/animals
-- ---------------------------------------------------------------------------

create function ade_animals(p_fazenda uuid, p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from animal where fazenda_id = p_fazenda;
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'resourceType', 'icarAnimalCoreResource',
      'meta', _ade_meta(a.id::text, a.criado_em, a.criado_em),
      'location', _ade_local(f),
      'identifier', _ade_animal(a, f),
      'alternativeIdentifiers', jsonb_build_array(jsonb_build_object('scheme', 'br.scara.uuid', 'id', a.id::text))
        || case when a.sisbov is not null
                then jsonb_build_array(jsonb_build_object('scheme', 'br.gov.sisbov', 'id', a.sisbov))
                else '[]'::jsonb end,
      'specie', 'Cattle',
      'gender', 'Female',
      'birthDate', case when a.nascimento is not null then _ade_data(a.nascimento, f.fuso) end,
      'primaryBreed', case when a.raca is not null then jsonb_build_object('scheme', 'br.scara.raca', 'id', a.raca) end,
      'managementTag', a.brinco,
      'name', a.nome,
      'productionPurpose', 'Milk',
      'status', case when a.baixa_em is null then 'Alive' when a.motivo_baixa = 'morte' then 'Dead' else 'OffFarm' end,
      'lactationStatus', case va.situacao when 'lactacao' then 'Lactating' when 'seca' then 'Dry' end
    )) order by a.brinco)
    into membros
    from (select * from animal where fazenda_id = p_fazenda order by brinco
           offset (p_pagina - 1) * p_tamanho limit p_tamanho) a
    join v_animal va on va.id = a.id;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

-- ---------------------------------------------------------------------------
-- Ordenhas · icarMilkingVisitEventResource · GET .../milking-visits
-- Só ordenhas válidas. Pesagem por equipamento não aprovado pela ICAR, declarado como tal.
-- ---------------------------------------------------------------------------

create function ade_milking_visits(p_fazenda uuid, p_desde date default null, p_ate date default null,
                                   p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from v_ordenha vo
   where vo.fazenda_id = p_fazenda and vo.valida
     and (p_desde is null or vo.data >= p_desde) and (p_ate is null or vo.data <= p_ate);
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'resourceType', 'icarMilkingVisitEventResource',
      'id', vo.id::text,
      'meta', _ade_meta(vo.id::text, vo.fim_em, vo.inicio_em),
      'location', _ade_local(f),
      'animal', _ade_animal(a, f),
      'eventDateTime', _ade_ts(vo.inicio_em),
      'milkingStartingDateTime', _ade_ts(vo.inicio_em),
      'milkingDuration', jsonb_build_object('unitCode', 'MIN',
                           'value', round(extract(epoch from vo.fim_em - vo.inicio_em) / 60.0, 1)),
      'milkingType', 'Manual',
      'milkingMilkWeight', jsonb_build_object('unitCode', 'KGM', 'value', round(vo.producao_g / 1000.0, 3)),
      'milkingComplete', vo.fechada,
      'milkingParlourUnit', (select string_agg(distinct po.numero::text, ',') from parcial p
                              join posto po on po.id = p.posto_id where p.ordenha_id = vo.id and not p.anulada),
      'measureDeviceId', (select string_agg(distinct p.posto_id::text, ',') from parcial p
                           where p.ordenha_id = vo.id and not p.anulada),
      'milkingShiftLocalStartDate', _ade_data_local(vo.data, f.fuso),
      'milkingShiftNumber', case vo.turno when 'manha' then 1 when 'tarde' then 2 else 3 end,
      'remark', case when vo.destino <> 'tanque' then 'destino: ' || vo.destino::text end
    )) order by vo.inicio_em)
    into membros
    from (select * from v_ordenha vo
           where vo.fazenda_id = p_fazenda and vo.valida
             and (p_desde is null or vo.data >= p_desde) and (p_ate is null or vo.data <= p_ate)
           order by vo.inicio_em offset (p_pagina - 1) * p_tamanho limit p_tamanho) vo
    join animal a on a.id = vo.animal_id;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

-- ---------------------------------------------------------------------------
-- Lactações · icarLactationResource · GET .../lactations
-- ---------------------------------------------------------------------------

create function ade_lactations(p_fazenda uuid, p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from lactacao l join animal a on a.id = l.animal_id where a.fazenda_id = p_fazenda;
  with lac as (
    select l.*, a,
           row_number() over (partition by l.animal_id order by l.data_parto) as parity,
           coalesce(l.data_secagem, least(current_date, coalesce(a.baixa_em, current_date))) as fim_calc
      from lactacao l join animal a on a.id = l.animal_id
     where a.fazenda_id = p_fazenda
     order by a.brinco, l.data_parto
    offset (p_pagina - 1) * p_tamanho limit p_tamanho
  )
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'resourceType', 'icarLactationResource',
      'id', lac.id::text,
      'meta', _ade_meta(lac.id::text, null, (lac.data_parto::timestamp) at time zone f.fuso),
      'location', _ade_local(f),
      'animal', _ade_animal(lac.a, f),
      'beginDate', _ade_data(lac.data_parto, f.fuso),
      'endDate', case when lac.data_secagem is not null then _ade_data(lac.data_secagem, f.fuso) end,
      'parity', lac.parity,
      'lactationLength', lac.fim_calc - lac.data_parto,
      'milkAmount', jsonb_build_object('unitCode', 'KGM', 'value',
        round(coalesce((select sum(vo.producao_g) from v_ordenha vo
                         where vo.animal_id = lac.animal_id and vo.valida
                           and vo.data between lac.data_parto and lac.fim_calc), 0) / 1000.0, 1)),
      'lactationType', 'Normal',
      'milkRecordingMethod', jsonb_build_object(
        'milkRecordingProtocol', 'B-HerdOwnerOrNominee',
        'milkRecordingScheme', 'AllMilkingsInPeriod',
        'milkingsPerDay', case when f.hora_corte_noite is null then '2' else '3' end,
        'recordingInterval', 1,
        'icarCertified', false,
        'milkingType', 'MeasureByNotApprovedEquipment')
    )) order by (lac.a).brinco, lac.data_parto)
    into membros
    from lac;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

-- ---------------------------------------------------------------------------
-- Partos e secagens · icarReproParturitionEventResource, icarMilkingDryOffEventResource
-- ---------------------------------------------------------------------------

create function ade_parturitions(p_fazenda uuid, p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from lactacao l join animal a on a.id = l.animal_id where a.fazenda_id = p_fazenda;
  with lac as (
    select l.*, a, row_number() over (partition by l.animal_id order by l.data_parto) as parity
      from lactacao l join animal a on a.id = l.animal_id
     where a.fazenda_id = p_fazenda
     order by l.data_parto, a.brinco
    offset (p_pagina - 1) * p_tamanho limit p_tamanho
  )
  select jsonb_agg(jsonb_build_object(
      'resourceType', 'icarReproParturitionEventResource',
      'id', 'parto-' || lac.id::text,
      'meta', _ade_meta('parto-' || lac.id::text, null, (lac.data_parto::timestamp) at time zone f.fuso),
      'location', _ade_local(f),
      'animal', _ade_animal(lac.a, f),
      'eventDateTime', _ade_data(lac.data_parto, f.fuso),
      'damParity', lac.parity
    ) order by lac.data_parto)
    into membros from lac;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

create function ade_dry_offs(p_fazenda uuid, p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from lactacao l join animal a on a.id = l.animal_id
   where a.fazenda_id = p_fazenda and l.data_secagem is not null;
  select jsonb_agg(jsonb_build_object(
      'resourceType', 'icarMilkingDryOffEventResource',
      'id', 'secagem-' || l.id::text,
      'meta', _ade_meta('secagem-' || l.id::text, null, (l.data_secagem::timestamp) at time zone f.fuso),
      'location', _ade_local(f),
      'animal', _ade_animal(a, f),
      'eventDateTime', _ade_data(l.data_secagem, f.fuso)
    ) order by l.data_secagem)
    into membros
    from (select l.* from lactacao l join animal a on a.id = l.animal_id
           where a.fazenda_id = p_fazenda and l.data_secagem is not null
           order by l.data_secagem offset (p_pagina - 1) * p_tamanho limit p_tamanho) l
    join animal a on a.id = l.animal_id;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

-- ---------------------------------------------------------------------------
-- Ração · icarFeedIntakeEventResource · GET .../feed-intakes
-- Programado vai em entitlement, fornecido em delivered. Estimado é declarado no remark.
-- ---------------------------------------------------------------------------

create function ade_feed_intakes(p_fazenda uuid, p_desde date default null, p_ate date default null,
                                 p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from v_racao r
   where r.fazenda_id = p_fazenda and r.fornecido_g is not null
     and (p_desde is null or r.data >= p_desde) and (p_ate is null or r.data <= p_ate);
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'resourceType', 'icarFeedIntakeEventResource',
      'id', 'racao-' || r.sessao_id::text || '-' || r.animal_id::text,
      'meta', _ade_meta('racao-' || r.sessao_id::text || '-' || r.animal_id::text, vo.fim_em, vo.inicio_em),
      'location', _ade_local(f),
      'animal', _ade_animal(a, f),
      'eventDateTime', _ade_ts(vo.inicio_em),
      'feedingStartingDateTime', _ade_ts(vo.inicio_em),
      'feedVisitDuration', jsonb_build_object('unitCode', 'MIN',
                             'value', round(extract(epoch from vo.fim_em - vo.inicio_em) / 60.0, 1)),
      'consumedFeed', jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'feedId', jsonb_build_object('scheme', 'br.scara.racao', 'id', 'concentrado'),
        'entitlement', case when r.programadas is not null
                            then jsonb_build_object('unitCode', 'KGM', 'value', round(r.programadas * r.massa_medida_g / 1000.0, 3)) end,
        'delivered', jsonb_build_object('unitCode', 'KGM', 'value', round(r.fornecido_g / 1000.0, 3))))),
      'remark', case when r.estimado then 'quantidade estimada: igual ao programado, sem conferência' end
    )) order by vo.inicio_em)
    into membros
    from (select * from v_racao r
           where r.fazenda_id = p_fazenda and r.fornecido_g is not null
             and (p_desde is null or r.data >= p_desde) and (p_ate is null or r.data <= p_ate)
           order by r.data, r.turno, r.brinco offset (p_pagina - 1) * p_tamanho limit p_tamanho) r
    join v_ordenha vo on vo.sessao_id = r.sessao_id and vo.animal_id = r.animal_id and vo.anulada_em is null
    join animal a on a.id = r.animal_id;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

-- ---------------------------------------------------------------------------
-- Lotes · icarAnimalSetResource e eventos de entrada e saída
-- ---------------------------------------------------------------------------

create function ade_animal_sets(p_fazenda uuid, p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from lote where fazenda_id = p_fazenda;
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'resourceType', 'icarAnimalSetResource',
      'id', l.id::text,
      'meta', _ade_meta(l.id::text, null, l.criado_em),
      'location', _ade_local(f),
      'name', l.nome,
      'reference', l.descricao,
      'purpose', 'Other',
      'member', coalesce((select jsonb_agg(_ade_animal(a, f) order by a.brinco)
                            from lote_animal la join animal a on a.id = la.animal_id
                           where la.lote_id = l.id and la.ate is null), '[]'::jsonb)
    )) order by l.nome)
    into membros
    from (select * from lote where fazenda_id = p_fazenda order by nome
           offset (p_pagina - 1) * p_tamanho limit p_tamanho) l;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

create function ade_animal_set_joins(p_fazenda uuid, p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from lote_animal la join lote l on l.id = la.lote_id where l.fazenda_id = p_fazenda;
  select jsonb_agg(jsonb_build_object(
      'resourceType', 'icarAnimalSetJoinEventResource',
      'id', 'entrada-' || la.lote_id::text || '-' || la.animal_id::text || '-' || la.desde::text,
      'meta', _ade_meta('entrada-' || la.lote_id::text || '-' || la.animal_id::text || '-' || la.desde::text,
                        null, (la.desde::timestamp) at time zone f.fuso),
      'location', _ade_local(f),
      'animal', _ade_animal(a, f),
      'animalSetId', la.lote_id::text,
      'eventDateTime', _ade_data(la.desde, f.fuso)
    ) order by la.desde)
    into membros
    from (select la.* from lote_animal la join lote l on l.id = la.lote_id
           where l.fazenda_id = p_fazenda order by la.desde offset (p_pagina - 1) * p_tamanho limit p_tamanho) la
    join animal a on a.id = la.animal_id;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

create function ade_animal_set_leaves(p_fazenda uuid, p_pagina int default 1, p_tamanho int default 1000) returns jsonb
language plpgsql stable security definer set search_path = scara, public, pg_temp as $$
declare
  f fazenda;
  membros jsonb;
  total bigint;
begin
  select * into strict f from fazenda where id = p_fazenda;
  select count(*) into total from lote_animal la join lote l on l.id = la.lote_id
   where l.fazenda_id = p_fazenda and la.ate is not null;
  select jsonb_agg(jsonb_build_object(
      'resourceType', 'icarAnimalSetLeaveEventResource',
      'id', 'saida-' || la.lote_id::text || '-' || la.animal_id::text || '-' || la.ate::text,
      'meta', _ade_meta('saida-' || la.lote_id::text || '-' || la.animal_id::text || '-' || la.ate::text,
                        null, (la.ate::timestamp) at time zone f.fuso),
      'location', _ade_local(f),
      'animal', _ade_animal(a, f),
      'animalSetId', la.lote_id::text,
      'eventDateTime', _ade_data(la.ate, f.fuso)
    ) order by la.ate)
    into membros
    from (select la.* from lote_animal la join lote l on l.id = la.lote_id
           where l.fazenda_id = p_fazenda and la.ate is not null
           order by la.ate offset (p_pagina - 1) * p_tamanho limit p_tamanho) la
    join animal a on a.id = la.animal_id;
  return _ade_colecao(membros, total, p_pagina, p_tamanho);
end $$;

-- Tudo de uma vez, para exportar em arquivo. Chaves são os caminhos da API ICAR.
create function ade_tudo(p_fazenda uuid, p_desde date default null, p_ate date default null) returns jsonb
language sql stable security definer set search_path = scara, public, pg_temp as $$
  select jsonb_build_object(
    'animals',           ade_animals(p_fazenda),
    'milking-visits',    ade_milking_visits(p_fazenda, p_desde, p_ate),
    'lactations',        ade_lactations(p_fazenda),
    'parturitions',      ade_parturitions(p_fazenda),
    'drying-offs',       ade_dry_offs(p_fazenda),
    'feed-intakes',      ade_feed_intakes(p_fazenda, p_desde, p_ate),
    'animal-sets',       ade_animal_sets(p_fazenda),
    'animal-set-joins',  ade_animal_set_joins(p_fazenda),
    'animal-set-leaves', ade_animal_set_leaves(p_fazenda))
$$;

-- ---------------------------------------------------------------------------
-- Controle leiteiro em formato de planilha, para GisLeite, IDEAGRI e similares
-- Uma linha por vaca e dia. Colunas neutras; o leiaute final fica em server/exportacao/leiautes.json.
-- ---------------------------------------------------------------------------

create view v_exportacao_controle_leiteiro as
select
  vo.fazenda_id,
  vo.animal_id,
  a.brinco                                            as numero,
  a.sisbov                                            as brinco_eletronico,
  a.nome,
  vo.data,
  round(sum(vo.producao_g) filter (where vo.turno = 'manha') / 1000.0, 2) as ordenha_1_kg,
  round(sum(vo.producao_g) filter (where vo.turno = 'tarde') / 1000.0, 2) as ordenha_2_kg,
  round(sum(vo.producao_g) filter (where vo.turno = 'noite') / 1000.0, 2) as ordenha_3_kg,
  round(sum(vo.producao_g) / 1000.0, 2)                                   as total_kg,
  round(sum(vo.producao_g) / 1000.0 / f.densidade_kg_l, 2)                as total_l,
  (select l.nome from lote_animal la join lote l on l.id = la.lote_id
    where la.animal_id = vo.animal_id and la.desde <= vo.data and (la.ate is null or la.ate > vo.data)) as lote,
  count(*)                                                                 as ordenhas
from v_ordenha vo
join animal a on a.id = vo.animal_id
join fazenda f on f.id = vo.fazenda_id
where vo.valida
group by vo.fazenda_id, vo.animal_id, a.brinco, a.sisbov, a.nome, vo.data, f.densidade_kg_l;

create view v_exportacao_animais as
select
  va.fazenda_id,
  va.id as animal_id,
  va.brinco as numero,
  va.sisbov as brinco_eletronico,
  va.nome,
  va.raca,
  va.nascimento,
  va.data_parto as ultimo_parto,
  (select count(*) from lactacao l where l.animal_id = va.id) as numero_de_partos,
  va.situacao,
  va.baixa_em,
  va.motivo_baixa,
  (select l.nome from lote_animal la join lote l on l.id = la.lote_id
    where la.animal_id = va.id and la.ate is null) as lote
from v_animal va;

-- ---------------------------------------------------------------------------
-- Permissões: só o painel autenticado exporta.
-- ---------------------------------------------------------------------------

grant execute on function
  ade_animals(uuid, int, int), ade_milking_visits(uuid, date, date, int, int), ade_lactations(uuid, int, int),
  ade_parturitions(uuid, int, int), ade_dry_offs(uuid, int, int), ade_feed_intakes(uuid, date, date, int, int),
  ade_animal_sets(uuid, int, int), ade_animal_set_joins(uuid, int, int), ade_animal_set_leaves(uuid, int, int),
  ade_tudo(uuid, date, date)
  to scara_operador;
grant select on v_exportacao_controle_leiteiro, v_exportacao_animais to scara_operador;

commit;
