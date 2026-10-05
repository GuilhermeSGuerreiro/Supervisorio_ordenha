#!/usr/bin/env python3
"""Valida arquivos exportados contra os esquemas JSON oficiais do ICAR ADE.

Uso:
  python3 tools/validar_ade.py <pasta com os .json das coleções> [--icar /caminho/para/adewg/ICAR]

O repositório do padrão é https://github.com/adewg/ICAR (clonar o branch ADE-1).
Também pode ser indicado pela variável de ambiente ICAR_ADE_DIR.
Valida cada coleção contra collections/<tipo>Collection.json e cada membro contra resources/<tipo>.json.
"""
import argparse
import json
import os
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

# Caminho da API ICAR -> recurso e coleção
TIPOS = {
    "animals":           ("icarAnimalCoreResource",         "icarAnimalCoreCollection"),
    "milking-visits":    ("icarMilkingVisitEventResource",  "icarMilkingVisitEventCollection"),
    "lactations":        ("icarLactationResource",          "icarLactationCollection"),
    "parturitions":      ("icarReproParturitionEventResource", "icarReproParturitionEventCollection"),
    "drying-offs":       ("icarMilkingDryOffEventResource", "icarMilkingDryOffEventCollection"),
    "feed-intakes":      ("icarFeedIntakeEventResource",    "icarFeedIntakeEventCollection"),
    "animal-sets":       ("icarAnimalSetResource",          "icarAnimalSetCollection"),
    "animal-set-joins":  ("icarAnimalSetJoinEventResource", "icarAnimalSetJoinEventCollection"),
    "animal-set-leaves": ("icarAnimalSetLeaveEventResource", "icarAnimalSetLeaveEventCollection"),
}


def registro(icar: Path) -> Registry:
    reg = Registry()
    for pasta in ("resources", "types", "enums", "collections"):
        for arq in (icar / pasta).glob("*.json"):
            uri = arq.resolve().as_uri()
            reg = reg.with_resource(uri, Resource.from_contents(json.loads(arq.read_text(encoding="utf-8")),
                                                                default_specification=DRAFT202012))
    return reg


def validador(icar: Path, reg: Registry, pasta: str, nome: str) -> Draft202012Validator:
    uri = (icar / pasta / f"{nome}.json").resolve().as_uri()
    return Draft202012Validator({"$ref": uri}, registry=reg, format_checker=FormatChecker())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pasta")
    ap.add_argument("--icar", default=os.environ.get("ICAR_ADE_DIR", "/opt/icar-ade"))
    args = ap.parse_args()
    icar = Path(args.icar)
    if not (icar / "resources").is_dir():
        print(f"repositório ICAR não encontrado em {icar}; clone https://github.com/adewg/ICAR", file=sys.stderr)
        return 2

    reg = registro(icar)
    erros = 0
    itens = 0
    for caminho, (recurso, colecao) in TIPOS.items():
        arq = Path(args.pasta) / f"{caminho}.json"
        if not arq.exists():
            print(f"{caminho}: arquivo ausente")
            continue
        dados = json.loads(arq.read_text(encoding="utf-8"))
        vcol = validador(icar, reg, "collections", colecao)
        vres = validador(icar, reg, "resources", recurso)
        falhas = [(e.json_path, e.message) for e in vcol.iter_errors(dados)]
        for i, membro in enumerate(dados.get("member", [])):
            itens += 1
            if membro.get("resourceType") != recurso:
                falhas.append((f"$.member[{i}].resourceType", f"esperado {recurso}"))
            for e in vres.iter_errors(membro):
                falhas.append((f"$.member[{i}]" + e.json_path[1:], e.message))
        if falhas:
            erros += len(falhas)
            print(f"{caminho}: {len(dados.get('member', []))} itens, {len(falhas)} erro(s)")
            for caminho_json, msg in falhas[:10]:
                print(f"   {caminho_json}: {msg}")
        else:
            print(f"{caminho}: {len(dados.get('member', []))} itens válidos")

    print(f"\n{itens} itens verificados, {erros} erro(s)")
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main())
