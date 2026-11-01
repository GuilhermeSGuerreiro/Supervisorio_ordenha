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
| Código | Firmware compila em ESP-IDF 5.3.6 sem avisos; banco com 17 cenários de teste passando; exportação ICAR validada |
| Semana 0 · bancada | não iniciada |
| Semanas 1–2 · conhecer a rotina | primeira visita feita em outubro de 2026, ver `docs/11-dados-de-campo.md` |
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
| `docs/11-dados-de-campo.md` | Visitas à fazenda: tempos observados, rodadas incompletas, hipóteses para reduzir o tempo da ordenha |
| `docs/08-mensuracao-manejo.md` | Como registrar uma mudança de manejo e medir o efeito: desenhos, confundidores, clima, detecção |
| `docs/10-plataforma-integrada.md` | Exportação em ICAR ADE e CSV para GisLeite e IDEAGRI, parceiros, governança do dado |
| `docs/09-impacto-setor.md` | Como a medição por vaca ajuda o setor: eficiência, genética, clima, emissões, crédito, e sugestões para o produto |
| `docs/07-viabilidade.md` | Estudo de viabilidade: soluções parecidas, norma ICAR, mercado regional, riscos e ajustes de rota |
| `hardware/` | Mecânica do posto, caixa, ligação elétrica |
| `firmware/posto-esp32/` | Firmware do posto (ESP32 + HX711), ESP-IDF 5.3 |
| `server/db/schema.sql` | Modelo de dados PostgreSQL do servidor local |
| `server/db/exportacao.sql` | Exportação em ICAR ADE 1.5 e visões de controle leiteiro para CSV |
| `server/db/fixture_demo.sql` | Dados de demonstração para testes e para mostrar o painel |
| `tools/coletar.py` | Coleta por aproximação: baixa os eventos do posto pelo Wi-Fi dele e grava no banco |
| `tools/exportar.py` e `tools/validar_ade.py` | Gera os arquivos de exportação e valida o JSON contra os esquemas oficiais do ICAR |
| `server/api/contrato.md` | Contrato HTTP entre posto, servidor e painel |
| `demo/video/` | Vídeo de demonstração: simulação no banco real, página animada e gravador |
| `planilhas/` | Lista de componentes e modelos CSV para validação, horas e custos |
| `tools/bom_totais.py` | Calcula os totais da lista de componentes e atualiza `docs/03-componentes.md` |

## Ideia central

Cada mudança de manejo é um experimento. O supervisório mede antes e depois, desconta lactação e calor, compara com o lote de controle e diz se funcionou. Ver `docs/08-mensuracao-manejo.md`.

## Arquitetura em uma linha

Etapa 1: ESP32 guarda pesos estáveis e toques do botão → o notebook vem até o posto, coleta pelo Wi-Fi do próprio ESP32 e grava no PostgreSQL local → o banco associa cada ordenha à vaca pela ordem fixa de entrada → exportação em ICAR ADE e CSV.

Etapa 2: os postos passam a enviar em tempo real a um servidor local, com painel no celular e sincronização opcional com a nuvem.

O posto não sabe qual vaca está sendo ordenhada. Toda a lógica de animal fica no servidor. Isso mantém o firmware simples e permite corrigir associações depois.
