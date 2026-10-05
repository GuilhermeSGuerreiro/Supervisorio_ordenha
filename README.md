# SCARA · Supervisório de ordenha balde ao pé

Piloto de medição de produção por vaca e apoio ao manejo em ordenha balde ao pé.
Fazenda piloto em Morada Nova-CE. Um posto primeiro, três depois.

## O que o produto responde

1. Quanto cada vaca produziu?
2. Quanto concentrado foi fornecido?
3. Qual animal mudou e merece atenção?
4. Como produção e gasto com concentrado estão evoluindo?

Fora do MVP: RFID, dosador automático, app nativo, IA, ordenha canalizada.

## Estado atual

| Etapa | Situação |
|---|---|
| Código | Firmware compila em ESP-IDF 5.3.6 sem avisos; esquema do banco com 13 cenários passando |
| Semana 0 · bancada | não iniciada |
| Semanas 1–2 · conhecer a rotina | não iniciada |
| Semanas 3–5 · um posto | não iniciada |
| Semanas 6–9 · três postos | não iniciada |

Primeiro compromisso: um posto funcionando, medição conferida e o operador registrando as ordenhas sozinho.

## Mapa do repositório

| Caminho | Conteúdo |
|---|---|
| `docs/00-revisao.md` | Inconsistências encontradas na versão inicial do plano e o que foi corrigido |
| `docs/01-escopo.md` | Contexto, cenário e escopo do MVP |
| `docs/02-operacao.md` | Fluxo operacional por posto, máquina de estados, regras de medição |
| `docs/03-componentes.md` | Lista de componentes (BOM) por posto e infraestrutura, com faixas de preço |
| `docs/04-validacao.md` | Protocolo de validação da balança, do uso e do manejo |
| `docs/05-plano-orcamento.md` | Cronograma por critério de avanço e orçamento por etapa |
| `docs/06-decisoes.md` | Decisões de arquitetura e seus motivos |
| `docs/08-mensuracao-manejo.md` | Como registrar uma mudança de manejo e medir o efeito: desenhos, confundidores, clima, detecção |
| `docs/09-impacto-setor.md` | Como a medição por vaca ajuda o setor: eficiência, genética, clima, emissões, crédito, e sugestões para o produto |
| `docs/07-viabilidade.md` | Estudo de viabilidade: soluções parecidas, norma ICAR, mercado regional, riscos e ajustes de rota |
| `hardware/` | Mecânica do posto, caixa, ligação elétrica |
| `firmware/posto-esp32/` | Firmware do posto (ESP32 + HX711), ESP-IDF 5.3 |
| `server/db/schema.sql` | Modelo de dados PostgreSQL do servidor local |
| `server/api/contrato.md` | Contrato HTTP entre posto, servidor e painel |
| `planilhas/` | Lista de componentes e modelos CSV para validação, horas e custos |
| `tools/bom_totais.py` | Calcula os totais da lista de componentes e atualiza `docs/03-componentes.md` |

## Ideia central

Cada mudança de manejo é um experimento. O supervisório mede antes e depois, desconta lactação e calor, compara com o lote de controle e diz se funcionou. Ver `docs/08-mensuracao-manejo.md`.

## Arquitetura em uma linha

ESP32 publica pesos estáveis → servidor local (Raspberry/PC, PostgreSQL) decide início, fim e produção → painel web no celular → sincronização opcional com a nuvem depois.

O posto não sabe qual vaca está sendo ordenhada. Toda a lógica de animal fica no servidor. Isso mantém o firmware simples e permite corrigir associações depois.
