#!/usr/bin/env python3
"""Exporta os dados de uma fazenda em ICAR ADE (JSON) e em CSV de controle leiteiro.

Uso:
  python3 tools/exportar.py --fazenda <uuid> --saida ./exportacao [--desde 2026-09-01] [--ate 2026-09-30]
                            [--db scara] [--leiaute ideagri,gisleite,generico]

Fala com o banco pelo psql, sem dependências extras. As variáveis PGHOST, PGUSER e PGPASSWORD
são respeitadas. Os arquivos ADE saem um por coleção, com o nome do caminho da API ICAR.
"""
import argparse
import csv
import json
import subprocess
import sys
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
LEIAUTES = json.loads((RAIZ / "server" / "exportacao" / "leiautes.json").read_text(encoding="utf-8"))


def psql_json(db: str, sql: str):
    saida = subprocess.run(
        ["psql", "-X", "-q", "-tA", "-v", "ON_ERROR_STOP=1", "-d", db, "-c", sql],
        check=True, capture_output=True, text=True).stdout.strip()
    return json.loads(saida) if saida else None


def formatar(valor, leiaute):
    if valor is None:
        return ""
    if isinstance(valor, bool):
        return "1" if valor else "0"
    if isinstance(valor, (int,)):
        return str(valor)
    if isinstance(valor, (float, Decimal)):
        return f"{valor:.2f}".replace(".", leiaute["decimal"])
    if isinstance(valor, str) and len(valor) == 10 and valor[4] == "-" and valor[7] == "-":
        try:
            return date.fromisoformat(valor).strftime(leiaute["data"])
        except ValueError:
            pass
    return str(valor)


def escrever_csv(linhas, leiaute, destino: Path):
    with destino.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f, delimiter=leiaute["separador"], quoting=csv.QUOTE_MINIMAL)
        w.writerow([c["cabecalho"] for c in leiaute["colunas"]])
        for linha in linhas:
            w.writerow([formatar(linha.get(c["campo"]), leiaute) for c in leiaute["colunas"]])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fazenda", required=True)
    ap.add_argument("--saida", required=True)
    ap.add_argument("--db", default="scara")
    ap.add_argument("--desde")
    ap.add_argument("--ate")
    ap.add_argument("--leiaute", default="ideagri,gisleite,generico")
    args = ap.parse_args()

    saida = Path(args.saida)
    (saida / "ade").mkdir(parents=True, exist_ok=True)
    (saida / "csv").mkdir(parents=True, exist_ok=True)
    desde = f"'{args.desde}'::date" if args.desde else "null"
    ate = f"'{args.ate}'::date" if args.ate else "null"

    # ICAR ADE: um arquivo por coleção.
    tudo = psql_json(args.db, f"select scara.ade_tudo('{args.fazenda}', {desde}, {ate})::text")
    for caminho, colecao in tudo.items():
        (saida / "ade" / f"{caminho}.json").write_text(
            json.dumps(colecao, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"ade/{caminho}.json: {colecao['view']['totalItems']} itens")

    # CSV de controle leiteiro, um por leiaute.
    filtro = f"fazenda_id = '{args.fazenda}'"
    if args.desde:
        filtro += f" and data >= '{args.desde}'"
    if args.ate:
        filtro += f" and data <= '{args.ate}'"
    controle = psql_json(args.db, f"""select coalesce(json_agg(t order by data, numero), '[]'::json)::text
                                        from scara.v_exportacao_controle_leiteiro t where {filtro}""")
    animais = psql_json(args.db, f"""select coalesce(json_agg(t order by numero), '[]'::json)::text
                                       from scara.v_exportacao_animais t where fazenda_id = '{args.fazenda}'""")

    for nome in args.leiaute.split(","):
        nome = nome.strip()
        if nome in LEIAUTES["controle_leiteiro"]:
            lay = LEIAUTES["controle_leiteiro"][nome]
            escrever_csv(controle, lay, saida / "csv" / f"controle_leiteiro_{nome}.csv")
            aviso = "  (leiaute a confirmar com o modelo oficial)" if lay.get("a_confirmar") else ""
            print(f"csv/controle_leiteiro_{nome}.csv: {len(controle)} linhas{aviso}")
        if nome in LEIAUTES["animais"]:
            escrever_csv(animais, LEIAUTES["animais"][nome], saida / "csv" / f"animais_{nome}.csv")
            print(f"csv/animais_{nome}.csv: {len(animais)} linhas")

    (saida / "exportacao.json").write_text(json.dumps({
        "fazenda": args.fazenda, "desde": args.desde, "ate": args.ate,
        "gerado_em": datetime.now().astimezone().isoformat(timespec="seconds"),
        "padrao": "ICAR ADE 1.5", "fonte": "br.scara"}, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
