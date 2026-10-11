#!/usr/bin/env python3
"""Roda a simulação no banco real e extrai os números do vídeo para dados.json.

Uso: python3 demo/video/gerar_dados.py [--db scara_demo_video]
Cria (e recria) o banco indicado. Precisa de psql com permissão para criar bancos.
"""
import argparse
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent.parent
FAZ = "00000000-0000-0000-0000-0000000d0001"
MUD = "00000000-0000-0000-0000-0000000dd001"


def psql(db, *args):
    return subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", db, *args],
                           check=True, capture_output=True, text=True).stdout


def consulta(db, sql):
    saida = psql(db, "-tA", "-c", f"select coalesce(json_agg(t), '[]'::json)::text from ({sql}) t").strip()
    return json.loads(saida)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="scara_demo_video")
    args = ap.parse_args()
    db = args.db

    subprocess.run(["dropdb", "--if-exists", db], check=True, capture_output=True)
    subprocess.run(["createdb", db], check=True)
    for arq in ["server/db/schema.sql", "server/db/exportacao.sql", "demo/video/simulacao.sql"]:
        psql(db, "-f", str(RAIZ / arq))

    dados = {}
    dados["vacas"] = consulta(db, f"""
        select brinco, round(avg(producao_g) / 1000.0, 1) as kg_dia
          from scara.v_producao_dia
         where fazenda_id = '{FAZ}' and data between '2026-09-15' and '2026-09-21'
         group by brinco order by brinco""")
    dados["lotes"] = consulta(db, f"""
        select pd.data::text as data,
               round(avg(pd.producao_g) filter (where la.lote_id is not null) / 1000.0, 2) as tratado,
               round(avg(pd.producao_g) filter (where la.lote_id is null) / 1000.0, 2) as controle
          from scara.v_producao_dia pd
          left join scara.lote_animal la on la.animal_id = pd.animal_id and la.ate is null
         where pd.fazenda_id = '{FAZ}'
         group by pd.data order by pd.data""")
    dados["clima"] = consulta(db, f"""
        select data::text as data, itu_medio, itu_max from scara.v_ambiente_dia
         where fazenda_id = '{FAZ}' order by data""")
    dados["efeito"] = consulta(db, f"""
        select titulo, desenho, n_tratadas, n_controle, base_g_vaca_dia, efeito_g_vaca_dia, efeito_pct,
               ic95_inf_g, ic95_sup_g, itu_base, itu_efeito, veredicto
          from scara.v_efeito_mudanca where id = '{MUD}'""")[0]
    dados["ingenuo"] = consulta(db, f"""
        select round(avg(delta_g))::int as delta_g from scara.v_efeito_mudanca_animal
         where mudanca_id = '{MUD}' and tratado and incluida""")[0]
    dados["tempos"] = consulta(db, f"""
        with ev as (
          select e.posto_id, e.tipo, e.ocorrido_em,
                 lag(e.tipo) over w as tipo_ant, lag(e.ocorrido_em) over w as em_ant
            from scara.evento_posto e join scara.posto p on p.id = e.posto_id
           where p.fazenda_id = '{FAZ}' and e.tipo in ('inicio', 'fim')
          window w as (partition by e.posto_id order by e.ocorrido_em)
        ),
        sessoes as (
          select s.id, min(ei.ocorrido_em) as ini, max(ef.ocorrido_em) as fim
            from scara.sessao s
            join scara.ordenha o on o.sessao_id = s.id
            join scara.parcial pa on pa.ordenha_id = o.id
            join scara.evento_posto ei on ei.id = pa.evento_inicio
            join scara.evento_posto ef on ef.id = pa.evento_fim
           where s.fazenda_id = '{FAZ}' group by s.id
        )
        select
          round(avg(extract(epoch from ocorrido_em - em_ant) / 60.0)
                filter (where tipo = 'fim' and tipo_ant = 'inicio')::numeric, 1) as maquina_min,
          round(avg(extract(epoch from ocorrido_em - em_ant) / 60.0)
                filter (where tipo = 'inicio' and tipo_ant = 'fim'
                          and ocorrido_em - em_ant < interval '1 hour')::numeric, 1) as troca_min,
          (select round(avg(extract(epoch from fim - ini) / 60.0)::numeric, 0) from sessoes) as sessao_min
        from ev""")[0]
    dados["contagens"] = consulta(db, f"""
        select (select count(*) from scara.evento_posto e join scara.posto p on p.id = e.posto_id
                 where p.fazenda_id = '{FAZ}') as eventos,
               (select count(*) from scara.v_ordenha where fazenda_id = '{FAZ}' and valida) as ordenhas_validas,
               (select count(*) from scara.v_ordenha where fazenda_id = '{FAZ}' and associacao = 'automatica') as automaticas,
               (scara.ade_milking_visits('{FAZ}') -> 'view' ->> 'totalItems')::int as ade_ordenhas,
               (select round(sum(producao_g) / 1000.0 / 21)::int from scara.v_producao_dia where fazenda_id = '{FAZ}') as rebanho_kg_dia""")[0]

    # Exporta em ICAR ADE e valida contra os esquemas oficiais, se o repositório do padrão estiver disponível.
    icar = os.environ.get("ICAR_ADE_DIR", "/opt/icar-ade")
    dados["ade"] = {"validado": False}
    if Path(icar, "resources").is_dir():
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["python3", str(RAIZ / "tools/exportar.py"), "--db", db, "--fazenda", FAZ, "--saida", tmp],
                           check=True, capture_output=True)
            r = subprocess.run(["python3", str(RAIZ / "tools/validar_ade.py"), f"{tmp}/ade", "--icar", icar],
                               capture_output=True, text=True)
            m = re.search(r"(\d+) itens verificados, (\d+) erro", r.stdout)
            if m:
                dados["ade"] = {"validado": True, "itens": int(m.group(1)), "erros": int(m.group(2))}

    (AQUI / "dados.json").write_text(json.dumps(dados, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({k: v for k, v in dados.items() if k not in ("lotes", "clima")}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
