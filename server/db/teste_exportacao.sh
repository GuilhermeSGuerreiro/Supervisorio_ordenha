#!/usr/bin/env bash
# Cria um banco temporário, aplica esquema, exportação e dados de demonstração,
# exporta em ICAR ADE e CSV e valida o JSON contra os esquemas oficiais.
# Uso: server/db/teste_exportacao.sh [nome_do_banco]
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="${1:-scara_exportacao_teste}"
SAIDA="$(mktemp -d)"

dropdb --if-exists "$DB"
createdb "$DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f server/db/schema.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f server/db/exportacao.sql
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f server/db/fixture_demo.sql >/dev/null

python3 tools/exportar.py --db "$DB" --fazenda 00000000-0000-0000-0000-00000000f001 --saida "$SAIDA"
echo
python3 tools/validar_ade.py "$SAIDA/ade"
echo
echo "CSV IDEAGRI, primeiras linhas:"
head -4 "$SAIDA/csv/controle_leiteiro_ideagri.csv"
echo "saída em $SAIDA"
