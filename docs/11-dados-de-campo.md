# Dados de campo

Registro das visitas à fazenda da prova de conceito. Cada visita entra com data, o que foi observado, a conta feita e o que ficou para confirmar.

## Visita de outubro de 2026

### Observado

| Item | Valor |
|---|---|
| Vacas no rebanho | cerca de 14 |
| Vacas ordenhadas | 9 |
| Vacas prenhes, fora da ordenha | 5 |
| Postos, um balde por posto | 3 |
| Rodadas na ordenha | 4 |
| Tempo total da ordenha | cerca de 60 min |
| Tempo de máquina por vaca | cerca de 5 min |

- Entre uma rodada e outra o operador abastece as tinas de ração da próxima vaca. Esse trabalho fica no caminho crítico: a vaca seguinte só entra depois.
- Algumas rodadas saíram com 2 vacas. Cada vaca tem posto fixo e, com as prenhes fora da fila, alguns postos ficam vazios.

### Conta

| Item | Por rodada | Na ordenha, 4 rodadas |
|---|---|---|
| Máquina ordenhando | 5 min | 20 min |
| Fora da máquina: troca, tinas, preparo, balde | 10 min | 40 min |
| Total | 15 min | 60 min |

Essa divisão supõe as rodadas sincronizadas nos três postos. Na prática o operador liga um posto de cada vez, as rodadas se desencontram e o tempo em que **nenhum** posto ordenha é menor que 40 min. O sistema mede as duas coisas separadamente; ver "Como o sistema mede" abaixo.

### Leituras

1. **A máquina não é o gargalo.** 5 min por vaca está dentro do normal, de 5 a 8 min. O ganho está na troca entre rodadas.
2. **Rodadas incompletas custam uma troca inteira.** 9 vacas cabem em 3 rodadas de 3. Fechar em 3 rodadas economizaria perto de 10 a 15 min por ordenha, sem custo.
3. **O tempo cresce com o rebanho.** Quando as prenhes parirem, serão cerca de 14 vacas em lactação: 5 rodadas no mínimo, 6 com posto fixo desbalanceado. No ritmo atual, 75 a 90 min por ordenha.
4. **Cada minuto cortado por rodada vale cerca de 50 horas por ano** com 4 rodadas e duas ordenhas por dia, e perto de 60 horas com 5 rodadas.

### Hipóteses a testar, da mais barata à mais cara

| # | Mudança | Custo | Métrica | Como medir |
|---|---|---|---|---|
| H1 | Balancear as rodadas: mover uma ou duas vacas de posto ou de posição na ordem | Zero | Rodadas por ordenha, ocupação dos postos, leite das vacas movidas | Antes e depois, aos poucos. Vaca é animal de hábito: observar descida do leite nos primeiros dias |
| H2 | Porções de ração preparadas antes da ordenha, em fila na ordem de entrada | Quase zero | Troca média por rodada | Mudança do tipo ordenha, antes e depois, 7 dias de cada lado |
| H3 | Dosador por gravidade em cada tina: reservatório com alavanca que solta uma porção medida | Serralheria simples, a cotar | Troca média por rodada | Só depois de H2 mostrar quanto do tempo é tina |
| H4 | Dosador acionado pelo posto, o módulo 2 | A orçar | Troca e precisão da ração | Depois da etapa 1 |

H2 dimensiona H3 e H4. Se as porções preparadas cortarem pouco, o dosador vale pela precisão da ração e não pelo tempo.

### A confirmar na próxima visita

- Se os 60 min incluem ligar e lavar o equipamento.
- Se as 5 prenhes estão secas e quando devem parir.
- Como a ração é servida: de onde vem, qual medida, quantas por vaca, a que distância fica o saco.
- Cronometrar duas ou três rodadas por trecho, em `planilhas/tempos.csv`.

| Trecho | Do momento | Até o momento |
|---|---|---|
| Saída e entrada | Teteira retirada | Vaca nova no lugar |
| Tinas | Começa a pegar a ração | Tina pronta |
| Preparo | Vaca no lugar | Teteira colocada |
| Máquina | Teteira colocada | Teteira retirada |

## Como o sistema mede

Com o posto instalado, o tempo sai dos toques do botão, sem cronômetro.

| Visão | O que mostra |
|---|---|
| `v_troca` | Cada parcial com rodada no posto, minutos de máquina, troca desde a vaca anterior e pausa de esvaziamento |
| `v_tempo_sessao` | Por ordenha: duração, rodadas feitas e mínimas, ocupação dos postos, máquina por vaca, troca média, tempo com algum posto ordenhando e tempo com nenhum |
| `v_efeito_tempo` | Para cada mudança de manejo: troca antes e depois, diferença com intervalo de confiança, ganho por ordenha e veredicto |

`rodadas_minimas` é o número de rodadas se os postos estivessem cheios. Quando `rodadas` passa de `rodadas_minimas`, há rodada incompleta: é o caso da hipótese H1.

`fora_maquina_min` é o tempo em que nenhum posto ordenhava. É o tempo morto puro, menor que a soma das trocas, porque um posto troca enquanto outro ordenha.
