# Operação por posto

Este documento define o que o operador faz, o que o posto mede e o que o servidor calcula.
As regras aqui são a referência para o firmware e para o servidor.

## Divisão de responsabilidades

| Parte | Faz | Não faz |
|---|---|---|
| Posto (ESP32) | Lê a célula, detecta estabilidade, registra toques do botão, guarda e reenvia | Não sabe qual vaca está no posto, não calcula produção |
| Servidor local | Associa leituras a vacas, calcula parciais e produção, valida, alerta | Não fala com a internet, salvo a sincronização de saída |
| Painel | Escolhe animal, lança ração e ocorrências, mostra os 3 cartões | Não é necessário para medir |

Se o celular estiver desligado, o posto continua gravando eventos e pesos.
O operador associa a vaca depois, pela ordem dos eventos.

## Condição padrão de leitura

Toda leitura de referência, de início ou de fim, segue a mesma condição:

1. Vácuo ligado.
2. Conjunto de teteiras pendurado no gancho do suporte, fora da plataforma.
3. Tubo longo drenado.
4. Ninguém tocando o balde ou a plataforma.

A mangueira de vácuo e o tubo longo ficam presos num ponto fixo do suporte, com laço de folga até a tampa.
Nenhuma mangueira apoia no piso entre o ponto fixo e o balde.

## Rotina de uma sessão

### Antes da primeira vaca

1. Ligar a bomba de vácuo.
2. Colocar o balde vazio na plataforma e conectar a tampa.
3. O posto mostra LED verde fixo quando a leitura está estável.
4. Toque longo no botão: o posto registra **balde colocado**. Esse peso é a tara da sessão.

### Para cada vaca

1. A vaca entra e começa a comer.
2. No celular, o operador toca a vaca na lista de próximas. Se não houver tempo, pula este passo.
3. Com o conjunto no gancho, toque curto no botão: **início**. O LED pisca até achar estabilidade e fica verde quando grava.
4. Colocar o conjunto na vaca e ordenhar.
5. Retirar o conjunto, levantar para drenar o tubo, pendurar no gancho.
6. Toque curto no botão: **fim**. O LED pisca até gravar.
7. Lançar ração, se diferente do programado, e ocorrências, se houver.

### Esvaziamento do balde

O painel mostra, em cada cartão, a capacidade restante até o limite operacional e a produção esperada da próxima vaca.
Se a próxima vaca não couber com margem, esvaziar antes de começar.

1. Toque longo no botão: **balde retirado**.
2. Esvaziar conforme o método da fazenda.
3. Recolocar o balde, conectar a tampa, aguardar o vácuo.
4. Toque longo: **balde colocado**. Nova tara.

### Esvaziamento no meio de uma vaca

Exceção. Só se o limite for atingido durante a ordenha.

1. Retirar o conjunto e pendurar no gancho.
2. Toque curto: **fim** da parcial.
3. Seguir o esvaziamento normal.
4. Toque curto: **início** da nova parcial e recolocar o conjunto.

O servidor percebe que a mesma vaca tem duas parciais com uma troca de balde entre elas e soma as duas.

## Botão e LED

| Ação | Evento | Uso |
|---|---|---|
| Toque curto | `marca` | Início ou fim, conforme o estado |
| Toque longo, 2 s | `balde` | Balde colocado ou retirado, conforme o estado |
| Toque longo, 6 s | `anula` | Anula o último evento, em caso de engano |

| LED | Significado |
|---|---|
| Verde, piscada curta a cada 2 s | Sem balde |
| Verde fixo | Ocioso, peso estável |
| Verde piscando rápido | Ocioso, peso ainda mexendo |
| Verde piscando lento | Ordenha em curso |
| Verde e vermelho piscando juntos | Aguardando estabilidade para gravar |
| Verde, piscadas rápidas por 1 s | Evento gravado |
| Vermelho piscando por 1 s | Ação recusada, como balde com ordenha aberta |
| Vermelho piscando sem parar | Erro: balança sem leitura, sem calibração, sobrecarga, falha de gravação ou chave recusada |
| Vermelho, piscada curta a cada 2 s | Sem Wi-Fi, gravando localmente |
| Verde e vermelho fixos com o botão apertado | Soltar agora registra balde |
| Vermelho fixo com o botão apertado | Soltar agora anula o último evento |

O LED é bicolor. Os padrões estão em `firmware/posto-esp32/main/main.cpp`, na função que atualiza o LED.

## Máquina de estados do posto

```
          balde colocado           marca
 SEM_BALDE ─────────────► OCIOSO ─────────► ORDENHANDO
     ▲                     │  ▲                 │
     │     balde retirado  │  │      marca      │
     └─────────────────────┘  └─────────────────┘
```

- `marca` em OCIOSO grava **início** e vai para ORDENHANDO.
- `marca` em ORDENHANDO grava **fim** e volta para OCIOSO.
- `balde` em OCIOSO grava **balde retirado** e vai para SEM_BALDE.
- `balde` em SEM_BALDE grava **balde colocado** e vai para OCIOSO.
- `balde` em ORDENHANDO é recusado com LED vermelho. O operador tem de marcar o fim antes.
- O estado é salvo na memória não volátil. Depois de um reinício, o posto volta ao estado em que estava.

## Estabilidade

O valor de cada evento é a primeira janela estável após o toque.

| Parâmetro | Valor inicial | Ajuste |
|---|---|---|
| Taxa do HX711 | 10 amostras/s | Mudar só se a bancada exigir |
| Janela | 40 amostras, 4 s | Deve cobrir vários ciclos do pulsador |
| Critério | Desvio padrão menor que 30 g | Ajustar na bancada e na sala |
| Valor gravado | Mediana da janela | |
| Tempo máximo de espera | 30 s | Depois disso grava com marca de instável |

Leituras marcadas como instáveis entram no banco, mas a ordenha fica pendente de conferência.

## Cálculo no servidor

- **Parcial** = peso estável no fim menos peso estável no início, sem troca de balde entre os dois.
- **Produção da ordenha** = soma das parciais da mesma vaca no mesmo turno.
- Se houver troca de balde entre início e fim da mesma parcial, a parcial é marcada como inconsistente.
- A tara do balde não entra na conta da produção. Ela serve para mostrar o nível do balde e checar a deriva.

## Associação com a vaca

1. Se o operador escolheu a vaca antes do início, a parcial já nasce associada.
2. Se não escolheu, a parcial fica sem animal e aparece no painel como pendente.
3. O painel sugere a vaca pela ordem habitual de entrada e pelo posto.
4. Ordenhas sem animal no fim do dia não contam como válidas.

## Registro válido

Uma ordenha é válida quando:

- tem animal identificado;
- todas as parciais têm início e fim estáveis;
- a produção está entre 0,3 kg e 40 kg;
- não foi anulada.

## Ração

- Cada vaca tem uma quantidade programada por turno, em medidas.
- A medida tem massa calibrada em kg, revista mensalmente ou quando a ração mudar.
- O operador lança o fornecido só quando difere do programado.
- Sem lançamento, o fornecido é igual ao programado e fica marcado como **estimado**.
- Campo opcional de sobra no cocho, em medidas, para quando houver sobra visível.

## Destino do leite

Cada ordenha tem destino: tanque, descarte, bezerro ou casa.
O padrão é tanque. Vacas com carência de medicamento registrada ficam com destino descarte até o fim da carência.

## Alertas

| Alerta | Regra inicial |
|---|---|
| Queda de produção | Duas ordenhas seguidas abaixo de 80% da média da vaca no mesmo turno nos últimos 7 dias |
| Vaca não ordenhada | Vaca em lactação sem ordenha válida no turno e sem ausência registrada |
| Ordenha pendente | Parcial sem animal ou com leitura instável |
| Deriva da balança | Tara do balde vazio difere mais de 300 g da tara de referência |
| Conciliação | Diferença entre postos e tanque maior que 5% no dia |

As regras são revistas na reunião semanal. Alerta que ninguém usa é desligado.

## Tempos a medir

Na semana 1, cronometrar sem o sistema e, depois da semana 6, com o sistema:

- duração da sessão do início ao fim;
- tempo por vaca, da entrada à saída;
- tempo gasto em esvaziamento de balde;
- tempo gasto no celular.
