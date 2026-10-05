# Plano e orçamento por etapa

Trabalho em tempo parcial. Cada etapa só começa quando o critério da anterior foi cumprido.
Se o critério falhar, a etapa se repete com ajuste, e a verba seguinte não é liberada.

## Etapas

### Semanas 1–2 · Conhecer a rotina e bancada

Na fazenda:
- Responder os pontos a confirmar listados em `docs/00-revisao.md`.
- Cadastrar animais com situação, data do parto e ordem habitual de entrada.
- Cronometrar 4 sessões sem o sistema.
- Pesar 10 medidas de concentrado e registrar a massa média.
- Medir a sala: distância até o servidor, sinal Wi-Fi, pontos de fixação, tomada para a fonte.

Em casa:
- Montar o posto 1 e rodar a fase 1 da validação, em bancada.
- Subir o servidor local com o banco e a ingestão de eventos.

**Avança se:** bancada aprovada e itens condicionais decididos.

### Semanas 3–5 · Um posto

- Instalar o posto 1 na sala, com fonte, cabeamento e ponto de acesso se necessário.
- Rodar a fase 2 da validação, com 30 comparações.
- O operador usa o posto 1 nas duas ordenhas do dia.

**Avança se:**
- fase 2 aprovada;
- tara do balde vazio repetível dentro de 100 g ao longo das sessões;
- o operador marca início e fim sozinho em pelo menos 10 sessões.

### Semanas 6–9 · Três postos

- Instalar os postos 2 e 3.
- Coleta nas duas ordenhas, em todos os postos.
- Começa a contagem dos 30 dias de uso.
- Fase 3 da validação, se houver balança de plataforma.
- Duas visitas a outras propriedades, para observar rotina.
- Cronometrar 4 sessões com o sistema na semana 9.

**Avança se:** operador sem ajuda constante, conforme `docs/04-validacao.md`.

### Meses 3–4 · Validar o manejo

- Completar 30 dias com 95% de registros válidos.
- Recalcular a tabela de detecção de `docs/08-mensuracao-manejo.md` com a variabilidade real.
- Primeira mudança de manejo com desenho escalonado por lote, escolhida com o operador.
- Segunda mudança, de outra categoria, no mês 4.
- Relatórios semanais, alertas e intervenções registradas.
- Revisão semanal com o operador.
- Sincronização opcional com a nuvem, só de saída.

**Avança se:**
- meta de 95% cumprida;
- pelo menos 4 revisões semanais registradas;
- pelo menos uma intervenção nascida de um alerta, registrada e acompanhada;
- pelo menos uma mudança de manejo com janela completa e veredicto emitido pelo sistema.

### Mês 5 · Visitas e documentação

- Visitar mais 1 a 3 propriedades, já com o sistema para mostrar.
- Documentar o kit: montagem, instalação, calibração, operação, manutenção.
- Escolher a fazenda do piloto externo.

### Mês 6 · Preparar piloto externo

- Kit documentado e testado por outra pessoa montando a partir do documento.
- Custo real do posto, a partir das notas fiscais e das horas registradas.
- Proposta comercial inicial.

### Dosador automático

Teste opcional num cocho, só depois da aprovação dos meses 3–4, com orçamento separado.
Não divide atenção com a validação do manejo.

## Liberação de verba

Valores com reserva de 20%, gerados a partir de `planilhas/bom.csv`.

| Liberação | Quando | O que cobre | Faixa provável |
|---|---|---|---|
| E1a | Início | Posto 1, fonte, cabo, armazenamento do servidor, suporte do celular, balança de referência, galões | Obrigatórios da E1: R$ 1.294 a 3.156 |
| E1b | Fim da semana 1 | Condicionais: ponto de acesso, DR, nobreak, relógio, balança de plataforma | R$ 0 a 1.428 |
| E2 | Aprovação das semanas 3–5 | Postos 2 e 3 e cabo adicional | R$ 1.404 a 3.612 |
| Dosador | Aprovação dos meses 3–4 | Orçamento próprio, fora desta tabela | — |

Regras:
- Só a E1a é liberada no início.
- A E1b depende das respostas da semana 1.
- A E2 depende do resultado do posto 1.
- Toda compra vai para `planilhas/custos.csv`, com nota fiscal quando houver.
- Toda hora trabalhada vai para `planilhas/horas.csv`. As horas entram no custo do produto futuro.

## Depois da validação

Não fazer agora. Registrado para não perder:

- Formalização. O limite do MEI é de R$ 81 mil por ano.
- Homologação na Anatel do equipamento com rádio. Usar módulo ESP32 já homologado ajuda.
- Vender como medidor para gestão, não como balança comercial, que exige aprovação do Inmetro.
- Editais de fomento: próximas edições do Centelha e do Startup Ceará.
