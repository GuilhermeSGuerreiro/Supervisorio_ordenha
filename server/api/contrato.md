# Contrato da API local

Servida pelo PostgREST sobre o esquema `scara`. Só existe na rede local, sem porta exposta à internet.
As funções estão em `server/db/schema.sql` e os cenários em `server/db/teste.sql`.

## Posto para servidor

Sem token. A chave do posto vai no corpo e é conferida pelo hash SHA-256.

### Enviar eventos

```
POST /rpc/ingerir
Content-Type: application/json
```

```json
{
  "p_chave": "48 caracteres hexadecimais",
  "p_boot": 12,
  "p_uptime_ms": 3600000,
  "p_eventos": [
    {
      "boot": 12,
      "seq": 3401,
      "tipo": "inicio",
      "massa_g": 23450,
      "bruto": 8123456,
      "estavel": true,
      "desvio_g": 12,
      "uptime_ms": 3590000,
      "epoch_ms": 1791187200000
    },
    {
      "boot": 12,
      "seq": 3402,
      "tipo": "anula",
      "ref_boot": 12,
      "ref_seq": 3401,
      "uptime_ms": 3595000
    }
  ]
}
```

| Campo | Regra |
|---|---|
| `p_boot`, `p_uptime_ms` | Estado atual do posto no momento do envio. Usados para estimar a hora de eventos sem `epoch_ms` |
| `tipo` | `inicio`, `fim`, `balde_colocado`, `balde_retirado`, `anula` |
| `massa_g` | Gramas, inteiro. Pode faltar se a leitura falhou. Nesse caso a parcial fica instável |
| `epoch_ms` | Só quando o posto tem hora sincronizada. Omitir se não tiver |
| `ref_boot`, `ref_seq` | Obrigatórios só em `anula` |
| Tamanho do lote | Até 200 eventos |

Resposta `200`:

```json
{ "boot": 12, "seq": 3402 }
```

É o último evento confirmado. O posto apaga da fila tudo até ele, inclusive.

| Situação | Resposta | O que o posto faz |
|---|---|---|
| Evento novo | Gravado e processado | Apaga da fila |
| Evento repetido | Ignorado, confirmado | Apaga da fila |
| Evento fora de sequência, como fim sem início | Gravado com erro, confirmado | Apaga da fila. O painel mostra a pendência |
| Chave inválida | `403` | Mantém a fila, tenta de novo em 60 s, LED de erro |
| Lote malformado | `400` | Mantém a fila e registra no serial. É bug de firmware |
| Servidor fora do ar | sem resposta | Mantém a fila, tenta de novo com espera crescente até 30 s |

### Enviar estado

```
POST /rpc/status_posto
```

```json
{
  "p_chave": "...",
  "p_status": {
    "massa_g": 34560,
    "estavel": true,
    "estado": "ORDENHANDO",
    "rssi": -61,
    "fila": 0,
    "boot": 12,
    "versao": "0.1.0"
  }
}
```

Resposta `200`:

```json
{ "boot_max": 12, "seq_max": 3402 }
```

São os maiores valores já recebidos desse posto. Em operação normal, `seq_max` nunca passa do seq do posto.
Se passar, a flash do posto foi apagada: o posto ajusta os contadores e reinicia antes de gerar eventos com chave repetida.

Enviado a cada 5 s com Wi-Fi conectado. Não é guardado como histórico, só o último valor.
O cartão do posto fica offline se o último estado tiver mais de 20 s.

### Enviar temperatura e umidade

```
POST /rpc/ingerir_ambiente
{ "p_chave": "...", "p_temperatura": 31.5, "p_umidade": 48.0 }
```

Só para posto com sensor de ambiente. Uma leitura a cada 10 minutos basta. O servidor calcula o ITU.

## Painel para servidor

### Login

```
POST /rpc/entrar
{ "p_pin": "482913" }
```

Resposta: o token como texto, ou `null` se o PIN estiver errado ou se houve 5 erros nos últimos 5 minutos.
O token vale 30 dias, configurável em `config_segura.jwt_dias`. Para revogar todos, trocar `jwt_segredo` no banco e no PostgREST.

Todas as chamadas seguintes levam:

```
Authorization: Bearer <token>
```

### Leituras principais

| Tela | Chamada |
|---|---|
| Cartões dos postos | `GET /v_cartao_posto?order=numero` |
| Pendências | `GET /v_pendencia?order=data.desc` |
| Ordenhas do dia | `GET /v_ordenha?data=eq.2026-10-05&order=turno,brinco` |
| Uso por sessão | `GET /v_uso_sessao?order=data.desc,turno.desc&limit=60` |
| Alertas de queda | `GET /v_alerta_queda` |
| Ração | `GET /v_racao?data=gte.2026-10-01` |
| Conciliação | `GET /v_conciliacao?order=coletado_em.desc` |
| Animais | `GET /v_animal?order=ordem_entrada` |
| Produção diária por vaca, com lote, dias em lactação e ITU | `GET /v_producao_dia?data=gte.2026-10-01` |
| Clima por dia | `GET /v_ambiente_dia?order=data.desc` |
| Efeito de cada mudança de manejo | `GET /v_efeito_mudanca?order=inicio.desc` |
| Efeito por vaca de uma mudança | `GET /v_efeito_mudanca_animal?mudanca_id=eq.<id>` |
| Mudanças que se sobrepõem | `GET /v_mudanca_sobreposta` |

Exportação em CSV: qualquer leitura acima com o cabeçalho `Accept: text/csv`.

### Ações

| Ação | Chamada |
|---|---|
| Escolher a vaca do posto | `POST /rpc/selecionar_animal` com `p_posto`, `p_animal` |
| Associar ordenha pendente | `POST /rpc/associar_animal` com `p_ordenha`, `p_animal` |
| Anular ordenha | `POST /rpc/anular_ordenha` com `p_ordenha`, `p_motivo` |
| Lançar ração fornecida | `POST /racao_fornecida` |
| Mudar destino do leite | `PATCH /ordenha?id=eq.<id>` com `destino` |
| Registrar ocorrência | `POST /ocorrencia` |
| Registrar intervenção | `POST /intervencao` |
| Cadastrar animal, parto, secagem, ausência | `POST` ou `PATCH` em `animal`, `lactacao`, `ausencia` |
| Registrar coleta do tanque | `POST /coleta_tanque` |
| Criar lote e mover vaca de lote | `POST /lote`, `POST /lote_animal` e `PATCH /lote_animal?animal_id=eq.<id>&ate=is.null` com `ate` |
| Registrar mudança de manejo | `POST /mudanca_manejo` |
| Encerrar mudança | `PATCH /mudanca_manejo?id=eq.<id>` com `fim` |
| Lançar clima manual ou do INMET | `POST /ambiente` com `origem` igual a `manual` ou `inmet` |
| Gerar nova chave de posto | `POST /rpc/nova_chave_posto` com `p_posto`. A chave aparece só nesta resposta |
