#!/usr/bin/env python3
"""Coleta por aproximação (D14): baixa os eventos de um posto e grava no banco.

Antes de rodar, conecte o computador ao Wi-Fi do posto (rede SCARA-POSTO-n).
O posto responde em http://192.168.4.1.

Uso:
  python3 tools/coletar.py --chave <chave do posto> [--posto http://192.168.4.1] [--db scara] [--copia ./coletas]

O que faz, nesta ordem:
  1. Acerta o relógio do posto com a hora deste computador.
  2. Baixa os eventos pendentes em lotes, grava cada lote no banco com scara.ingerir e confirma no posto.
  3. Guarda uma cópia bruta de cada lote em JSON na pasta de cópias, antes de gravar no banco.
  4. Informa ao posto o maior boot e seq que o banco conhece, para o posto se corrigir se a flash for apagada.

Só precisa de psql no caminho. Sem dependências extras.
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path


def http(metodo: str, url: str, chave: str, corpo=None, timeout=10):
    dados = json.dumps(corpo).encode() if corpo is not None else None
    req = urllib.request.Request(url, data=dados, method=metodo,
                                 headers={"X-Chave": chave, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def psql_json(db: str, sql: str):
    saida = subprocess.run(["psql", "-X", "-q", "-tA", "-v", "ON_ERROR_STOP=1", "-d", db, "-c", sql],
                           check=True, capture_output=True, text=True).stdout.strip()
    return json.loads(saida) if saida else None


def sql_texto(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--chave", required=True, help="chave do posto, a mesma gravada no ESP32 e no banco")
    ap.add_argument("--posto", default="http://192.168.4.1")
    ap.add_argument("--db", default="scara")
    ap.add_argument("--copia", default="./coletas", help="pasta para a cópia bruta dos lotes")
    ap.add_argument("--lote", type=int, default=200)
    args = ap.parse_args()

    try:
        info = http("GET", f"{args.posto}/info", args.chave)
    except urllib.error.URLError as e:
        print(f"não achei o posto em {args.posto}: {e}. Está conectado na rede SCARA-POSTO-n?", file=sys.stderr)
        return 2
    print(f"posto {info['posto']}  versão {info['versao']}  boot {info['boot']}  pendentes {info['pendentes']}  "
          f"hora_ok {info['hora_ok']}  rtc {info['rtc']}")

    # 1. Relógio
    agora_ms = int(time.time() * 1000)
    info = http("POST", f"{args.posto}/hora", args.chave, {"epoch_ms": agora_ms})
    desvio = (info.get("epoch_ms", agora_ms) - agora_ms) / 1000
    print(f"relógio acertado (diferença após acerto: {desvio:+.1f} s)")

    # 2. Eventos
    pasta = Path(args.copia)
    pasta.mkdir(parents=True, exist_ok=True)
    total = 0
    rodada = 0
    while True:
        lote = http("GET", f"{args.posto}/eventos?max={args.lote}", args.chave, timeout=30)
        eventos = lote["eventos"]
        if not eventos:
            break
        rodada += 1
        carimbo = datetime.now().strftime("%Y%m%d-%H%M%S")
        (pasta / f"posto{info['posto']}-{carimbo}-{rodada:03d}.json").write_text(
            json.dumps(lote, ensure_ascii=False, indent=1), encoding="utf-8")

        ack = psql_json(args.db, f"select scara.ingerir({sql_texto(args.chave)}, {lote['boot']}, "
                                 f"{int(lote['uptime_ms'])}, {sql_texto(json.dumps(eventos))}::jsonb)::text")
        maximos = psql_json(args.db, f"select scara.status_posto({sql_texto(args.chave)}, "
                                     f"{sql_texto(json.dumps({'estado': 'COLETA', 'fila': lote['pendentes']}))}::jsonb)::text")
        http("POST", f"{args.posto}/confirmar", args.chave,
             {"boot": ack["boot"], "seq": ack["seq"], "boot_max": maximos["boot_max"], "seq_max": maximos["seq_max"]})
        total += len(eventos)
        print(f"lote {rodada}: {len(eventos)} eventos gravados e confirmados até {ack['boot']}/{ack['seq']}")

    info = http("GET", f"{args.posto}/info", args.chave)
    print(f"concluído: {total} eventos coletados, {info['pendentes']} pendentes no posto")
    return 0 if info["pendentes"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
