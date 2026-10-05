#!/usr/bin/env python3
"""Calcula os totais da lista de componentes por etapa.

Uso:
    python3 tools/bom_totais.py              imprime as tabelas
    python3 tools/bom_totais.py --atualizar  reescreve a seção gerada em docs/03-componentes.md

- Mínimo: só itens obrigatórios, preço mínimo.
- Máx. obrig.: só itens obrigatórios, preço máximo.
- Máx. total: obrigatórios e condicionais, preço máximo. É o pior caso.
- Reserva de 20% sobre cada valor.
"""
import csv
import io
import sys
from collections import defaultdict
from contextlib import redirect_stdout
from pathlib import Path

RESERVA = 0.20
RAIZ = Path(__file__).resolve().parent.parent
CAMINHO = RAIZ / "planilhas" / "bom.csv"
DOC = RAIZ / "docs" / "03-componentes.md"
INICIO, FIM = "<!-- bom:inicio -->", "<!-- bom:fim -->"


def brl(v: float) -> str:
    return f"R$ {v:,.0f}".replace(",", ".")


def tabelas() -> None:
    # [min obrigatorio, max obrigatorio, max com condicionais]
    tot = defaultdict(lambda: [0.0, 0.0, 0.0])
    with CAMINHO.open(encoding="utf-8") as f:
        for linha in csv.DictReader(f):
            qtd = int(linha["qtd"])
            pmin = float(linha["preco_unit_min"]) * qtd
            pmax = float(linha["preco_unit_max"]) * qtd
            if pmin > pmax:
                raise SystemExit(f"preco minimo maior que maximo em {linha['item']}")
            chave = (linha["etapa"], linha["grupo"])
            if linha["condicao"] == "obrigatorio":
                tot[chave][0] += pmin
                tot[chave][1] += pmax
            elif linha["condicao"] != "condicional":
                raise SystemExit(f"condicao invalida: {linha['condicao']!r} em {linha['item']}")
            tot[chave][2] += pmax

    print("| Etapa | Grupo | Mínimo | Máx. obrig. | Máx. total |")
    print("|---|---|---|---|---|")
    por_etapa = defaultdict(lambda: [0.0, 0.0, 0.0])
    for (etapa, grupo), vals in sorted(tot.items()):
        print(f"| {etapa} | {grupo} | " + " | ".join(brl(v) for v in vals) + " |")
        for i, v in enumerate(vals):
            por_etapa[etapa][i] += v

    r = 1 + RESERVA
    print()
    print(f"Com reserva de {RESERVA:.0%}:")
    print()
    print("| Etapa | Mínimo | Máx. obrig. | Máx. total |")
    print("|---|---|---|---|")
    geral = [0.0, 0.0, 0.0]
    for etapa, vals in sorted(por_etapa.items()):
        print(f"| {etapa} | " + " | ".join(brl(v * r) for v in vals) + " |")
        geral = [g + v for g, v in zip(geral, vals)]
    print("| **Total** | " + " | ".join(brl(v * r) for v in geral) + " |")


def main() -> None:
    if "--atualizar" not in sys.argv:
        tabelas()
        return
    buf = io.StringIO()
    with redirect_stdout(buf):
        tabelas()
    texto = DOC.read_text(encoding="utf-8")
    a, b = texto.index(INICIO) + len(INICIO), texto.index(FIM)
    DOC.write_text(texto[:a] + "\n" + buf.getvalue() + texto[b:], encoding="utf-8")
    print(f"atualizado: {DOC.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
