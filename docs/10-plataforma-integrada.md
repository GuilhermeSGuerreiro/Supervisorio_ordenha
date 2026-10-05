# Plataforma integrada

O objetivo é melhorar a vida do produtor de leite do semiárido. Nenhum sistema faz isso sozinho.
O supervisório gera o dado primário, a produção de cada vaca em cada ordenha, e entrega esse dado a quem já ajuda o produtor: o técnico, o laticínio, o programa de melhoramento, o banco.

## Princípio

**O dado é do produtor.** O supervisório guarda, organiza e exporta. Cada envio para fora da fazenda é autorizado pelo produtor, por parceiro, e pode ser revogado. Isso é o que a Lei Geral de Proteção de Dados pede e é o que mantém a confiança.

## Como os dados saem

```
 posto ──► servidor local ──► exportação ──┬──► ICAR ADE (JSON)  ──► controle leiteiro, melhoramento genético, outros softwares
                                           ├──► CSV de controle leiteiro ──► GisLeite, IDEAGRI, planilhas
                                           └──► relatório em PDF ──► técnico, laticínio, banco
```

Duas saídas já existem no banco e estão testadas:

| Saída | O que é | Para quem |
|---|---|---|
| **ICAR ADE 1.5** | Padrão internacional aberto de troca de dados animais, em JSON. Mantido pelo Comitê Internacional de Registro Animal, licença Apache 2.0 | Serviços de controle leiteiro, programas de melhoramento, softwares de gestão que já falam ADE, robôs e medidores de outras marcas |
| **CSV de controle leiteiro** | Uma linha por vaca e dia, com as ordenhas separadas, nos leiautes de importação do IDEAGRI e do GisLeite | Produtor que já usa esses sistemas, técnico que consolida várias fazendas |

### ICAR ADE

O que é exportado e de onde vem:

| Coleção ICAR | Recurso | Origem no banco |
|---|---|---|
| `animals` | icarAnimalCoreResource | animal, lactação aberta |
| `milking-visits` | icarMilkingVisitEventResource | ordenhas válidas, com peso em kg, duração, posto e turno |
| `lactations` | icarLactationResource | lactação, com paridade, duração e leite acumulado |
| `parturitions` | icarReproParturitionEventResource | data do parto |
| `drying-offs` | icarMilkingDryOffEventResource | data de secagem |
| `feed-intakes` | icarFeedIntakeEventResource | ração programada e fornecida, com aviso quando estimada |
| `animal-sets` | icarAnimalSetResource | lotes e seus membros atuais |
| `animal-set-joins`, `animal-set-leaves` | eventos de entrada e saída de lote | histórico de alocação |

Decisões de identificação, seguindo o guia de identificadores do padrão:

- **Local**: esquema oficial quando cadastrado, como a inscrição estadual. Senão, `br.scara.fazenda` com o código da fazenda.
- **Animal**: não há esquema nacional obrigatório para leite. O padrão recomenda, nesse caso, o composto `composite.withinherdid`, que é `código da fazenda.brinco`. O número SISBOV, quando houver, vai como identificador alternativo em `br.gov.sisbov`.
- **Método de medição**: declarado como `MeasureByNotApprovedEquipment`, protocolo B, todas as ordenhas do período, intervalo de um dia. É a verdade do piloto. Se um dia o posto for certificado, muda-se um campo.
- **Datas**: UTC com Z, como o padrão exige. A data local do turno vai com o deslocamento do fuso da fazenda.

Toda coleção sai validada contra os esquemas oficiais pelo `tools/validar_ade.py`. O teste de ponta a ponta está em `server/db/teste_exportacao.sh`.

Pela API local, cada coleção é uma função: `GET /rpc/ade_milking_visits?p_fazenda=...&p_desde=2026-09-01`. Quem precisar dos caminhos exatos do padrão, `/locations/{scheme}/{id}/milking-visits`, coloca um redirecionamento no servidor web na frente do PostgREST. Isso fica para quando houver um parceiro consumindo.

### CSV para GisLeite e IDEAGRI

- A visão `v_exportacao_controle_leiteiro` tem uma linha por vaca e dia, com primeira, segunda e terceira ordenha em kg, total em kg e em litros, e lote.
- Os leiautes ficam em `server/exportacao/leiautes.json`: cabeçalhos, ordem, separador, decimal e formato de data. Para ajustar ao modelo que o sistema de destino fornece, edita-se esse arquivo, não o código.
- O leiaute do IDEAGRI segue a documentação pública de importação, com identificação pelo número do animal.
- **O leiaute do GisLeite está marcado como "a confirmar".** O modelo oficial é baixado dentro do GisLeite Web, na tela de controle leiteiro, e não foi possível acessá-lo deste ambiente. Primeira tarefa ao abrir uma conta no GisLeite: baixar o modelo, copiar os cabeçalhos para o arquivo de leiautes e rodar a exportação.
- Os sistemas de gestão trabalham em litros e o posto mede em kg. O CSV traz os dois, com a densidade cadastrada na fazenda.

Comando:

```
python3 tools/exportar.py --fazenda <id> --saida ./exportacao --desde 2026-09-01 --ate 2026-09-30
```

Gera a pasta `ade/` com um arquivo por coleção, a pasta `csv/` com um arquivo por leiaute e um `exportacao.json` com a descrição do lote.

## Quem pode se ligar

| Parceiro | O que recebe | O que devolve ao produtor | Como |
|---|---|---|---|
| Técnico de assistência, Senar ATeG, Balde Cheio | Produção por vaca, alertas, efeito das mudanças | Orientação com base em dado, não em memória | Acesso ao painel ou CSV mensal |
| Laticínio | Produção diária prevista, vacas em carência | Logística de coleta, programa de qualidade, bonificação | ADE ou relatório; só com autorização do produtor |
| Programa de melhoramento, Girolando, Embrapa | Lactações completas de vacas identificadas | Avaliação genética do rebanho, escolha de touro | ADE `lactations` e `animals` |
| GisLeite, IDEAGRI e similares | Controle leiteiro diário | Relatórios zootécnicos e econômicos que o supervisório não faz | CSV |
| Banco, Pronaf | Histórico de produção assinado pelo sistema | Crédito com base em dado | Relatório em PDF, a construir |
| Outras fazendas com o sistema | Nada identificável | Comparativo anônimo | Nuvem, só com três ou mais fazendas |

## O que falta construir

| Item | Quando |
|---|---|
| Autorização por parceiro no painel, com registro de quem recebeu o quê | Antes do primeiro envio para fora da fazenda |
| Confirmar o leiaute do GisLeite com o modelo oficial | Ao abrir a conta, semana 2 |
| Relatório em PDF para técnico, laticínio e banco | Mês 5 |
| Servidor na nuvem recebendo ADE das fazendas, com a mesma validação | Mês 5 |
| Caminhos oficiais da API ICAR no servidor web | Quando houver parceiro consumindo |
| Importar o que vem de fora: controle leiteiro oficial, análises de leite do laticínio | Depois do piloto externo |
