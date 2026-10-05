# Revisão do plano inicial · operação e componentes

Este documento lista as inconsistências encontradas na primeira versão do plano e a correção adotada.
Os demais documentos em `docs/` já incorporam as correções.

Legenda de gravidade:

- **Alta**: invalida a medição ou o critério de validação se não for corrigida.
- **Média**: gera retrabalho, custo escondido ou atrito na operação.
- **Baixa**: ajuste de texto, prazo ou clareza.

## Resumo

| # | Tema | Gravidade |
|---|---|---|
| 1 | Mangueira de vácuo "nunca no balde" é fisicamente impossível | Alta |
| 2 | Célula de 100 kg sem margem para tara e impacto | Alta |
| 3 | Leitura de início e fim sem condição padronizada | Alta |
| 4 | Bezerro ao pé não considerado | Alta |
| 5 | Conciliação com o tanque ignora leite descartado e erro da régua | Alta |
| 6 | Pausa no meio da vaca é exceção, não fluxo normal | Média |
| 7 | Orçamento do primeiro posto não inclui a infraestrutura que ele exige | Média |
| 8 | Raspberry com cartão SD e energia rural instável | Média |
| 9 | Alimentação "baixa tensão" sem definição de distribuição | Média |
| 10 | Celular pessoal como único meio de operação na sala | Média |
| 11 | Cadastro sem situação do animal, mas a meta de 95% depende dela | Média |
| 12 | Ração "fornecida" sem método de medida | Média |
| 13 | Protocolo das 30 comparações não diz como comparar | Média |
| 14 | "Registro válido" não definido | Média |
| 15 | Alertas comparando manhã com tarde | Média |
| 16 | "Sincroniza depois" ambíguo e em tensão com "sem internet" | Baixa |
| 17 | Meta de 95% em 30 dias sem etapa atribuída | Baixa |
| 18 | Visitas a propriedades sem prazo | Baixa |
| 19 | Taxa de amostragem do HX711 sugerida na conversa anterior | Baixa |
| 20 | Capacidade nominal de 70 L versus enchimento real e esvaziamento | Média |
| 21 | Balança de referência exigida na validação, mas sem linha no orçamento | Média |
| 22 | Relógio do servidor e dos postos sem internet | Média |

## Detalhamento

### 1. Mangueira de vácuo "nunca no balde"

**Problema.** No balde ao pé, o pulsador fica na tampa e a mangueira de vácuo se conecta à tampa.
A mangueira precisa chegar ao balde. O que importa é ela não transmitir força variável à balança.
A mangueira também enrijece quando o vácuo é aplicado, e isso muda a força que ela exerce.

**Correção.** A mangueira de vácuo e o tubo longo de leite são presos num ponto fixo do suporte, fora da plataforma.
Do ponto fixo até a tampa fica um laço de folga, sem esticar e sem apoiar no piso.
Toda leitura de referência é feita com o vácuo ligado, para que a rigidez da mangueira seja a mesma no início e no fim.

### 2. Capacidade da célula

**Problema.** A faixa de 100 a 150 kg admite 100 kg.
Conta da carga estática máxima:

| Item | Massa estimada |
|---|---|
| 70 L de leite a 1,032 kg/L | 72,2 kg |
| Balde inox 70 L | 8 a 14 kg |
| Tampa, pulsador, conexões | 3 a 5 kg |
| Plataforma sobre a célula | 3 a 8 kg |
| **Total estático** | **86 a 99 kg** |

Com 100 kg a célula trabalha no limite.
Colocar o balde cheio com um tranco, ou o operador se apoiar, facilmente passa de 1,5 vez a carga estática.

**Correção.** Célula single point de **150 kg no mínimo**, 200 kg aceitável.
Batente mecânico de sobrecarga 1 a 2 mm abaixo da plataforma.
A plataforma máxima declarada na ficha da célula tem de ser igual ou maior que a plataforma real.
A resolução continua sobrando: com o HX711, o ruído elétrico fica na casa de poucos gramas, e o limite real é mecânico.

### 3. Leitura de início e fim

**Problema.** "Peso no fim menos peso no início" só funciona se as duas leituras forem feitas na mesma condição.
Variam entre elas: conjunto de teteiras pendurado ou na mão, vácuo ligado ou desligado, leite parado no tubo, vaca encostando no balde.

**Correção.** Condição padrão de leitura, igual no início e no fim:

1. Vácuo ligado.
2. Conjunto de teteiras pendurado no gancho do suporte, fora da plataforma.
3. Tubo longo drenado, com o conjunto levantado por alguns segundos após a retirada.
4. Ninguém tocando o balde ou a plataforma.

O operador marca o evento com um toque ou botão. O valor gravado é a primeira janela estável após o toque.
Na conversa anterior foi sugerido detectar início e fim só pela estabilidade do peso. Isso foi revisto: o fim do fluxo é lento e a balança fica "estável" antes de a vaca terminar. O toque marca o evento e a estabilidade define o valor.

### 4. Bezerro ao pé

**Problema.** Em rebanhos mestiços do semiárido é comum o bezerro mamar antes ou depois da ordenha para estimular a descida do leite.
Se isso acontece na fazenda piloto, o sistema mede leite ordenhado, não produção total.
Comparar vacas com e sem bezerro, ou a mesma vaca em dias diferentes, gera alertas falsos.

**Correção.** Verificar na semana 1.
Se houver bezerro, o cadastro do animal ganha o campo "ordenha com bezerro" e os relatórios dizem "leite ordenhado".
Alertas comparam a vaca só com ela mesma, na mesma condição.

### 5. Conciliação com o tanque

**Problema.** A soma dos postos só bate com o tanque se todo leite pesado for para o tanque.
Leite de vaca em tratamento com antibiótico, colostro, leite para bezerros e para a casa saem do balde e não vão ao tanque.
A régua do tanque tem erro próprio, frequentemente de 1 a 2%, e o volume precisa de conversão para massa.

**Correção.**
- Cada ordenha tem o campo **destino**: tanque, descarte, bezerro, casa.
- A conciliação usa só o destino tanque.
- Conversão com densidade de 1,032 kg/L, registrada como parâmetro.
- Referência principal: o ticket de coleta do laticínio, quando houver. A régua fica como referência secundária.
- A conciliação serve para achar erro grosseiro, como um posto descalibrado. Ela não valida a meta de 200 g por vaca.

### 6. Pausa no meio da vaca

**Problema.** O plano trata o esvaziamento como pausa que guarda o subtotal da vaca.
Na prática, esvaziar no meio da ordenha exige tirar o conjunto e desligar o vácuo, o que atrapalha a vaca.
Um balde cheio demais também arrisca leite no interceptor e na linha de vácuo.

**Correção.**
- Regra operacional: antes de colocar a próxima vaca, o painel mostra a capacidade restante e a produção esperada dela no mesmo turno. Se não couber com margem, esvazia antes.
- A pausa com subtotal continua no sistema, mas como exceção.
- O sistema modela a ordenha como uma ou mais **parciais**. Cada parcial tem início e fim estáveis. A produção é a soma das parciais.

### 7. Orçamento do primeiro posto

**Problema.** A regra é liberar só a verba do primeiro posto, de R$ 700 a 1.500.
Mas o posto 1 já precisa de fonte, cabeamento, cobertura Wi-Fi na sala, armazenamento confiável no servidor e balança de referência.
No plano, tudo isso está em "completar 3 postos + infraestrutura".
Há também uma inconsistência aritmética: dois postos a R$ 700–1.500 cada somam R$ 1.400–3.000, mais que o teto de R$ 2.500 que deveria incluir a infraestrutura.

**Correção.** O orçamento foi reorganizado por etapa, com a infraestrutura mínima dentro da etapa 1.
A lista de componentes virou planilha, e os totais são calculados por script.

| Faixa, com reserva de 20% | Plano inicial | Revisado |
|---|---|---|
| Etapa 1: posto 1 + infra mínima + validação | R$ 700–1.500, sem infra e sem reserva | R$ 1.294–3.156 |
| Etapa 2: postos 2 e 3 | dentro de R$ 1.300–2.500 | R$ 1.404–3.612 |
| Total, só obrigatórios | R$ 2.580–5.280 | R$ 2.698–6.768 |
| Total, pior caso com condicionais | não previsto | R$ 8.196 |

O piso quase não mudou. O teto subiu porque agora inclui o que faltava.
O teto real depende das respostas da semana 1: sinal Wi-Fi, quedas de energia e proteção do circuito existente.
Ver `docs/03-componentes.md` e `planilhas/bom.csv`.

### 8. Raspberry com cartão SD

**Problema.** Queda de energia é frequente na zona rural. Raspberry com cartão SD corrompe o sistema de arquivos com facilidade, e o PostgreSQL perde dados.
O plano exige "não perder nem duplicar dados após reinício", mas não protege o servidor.

**Correção.**
- Banco em SSD USB, ou no mínimo cartão de alta durabilidade.
- Nobreak para servidor e ponto de acesso, obrigatório se a semana 1 mostrar quedas frequentes.
- Cópia de segurança diária automática para pendrive e semanal para fora da fazenda.
- Se o servidor for um PC, a mesma regra de nobreak vale.

### 9. Alimentação elétrica

**Problema.** "Baixa tensão" não define a topologia. Um carregador USB por posto exige tomada 127/220 V perto da área molhada.
Distribuir 5 V por cabo longo dá queda de tensão e reinício do ESP32 quando o Wi-Fi transmite.

**Correção.**
- Uma fonte chaveada de 12 V em local seco, alimentada por circuito com disjuntor e DR de 30 mA.
- Distribuição em 12 V até cada posto, com conversor 12→5 V dentro da caixa.
- Estrutura metálica aterrada. Circuito separado do motor da bomba de vácuo, ou pelo menos com filtro.

### 10. Operação só pelo celular

**Problema.** Com três vacas ao mesmo tempo, o operador está com as mãos molhadas e ocupadas.
O celular pessoal recebe chamadas, descarrega e cai no chão.
Cada toque a mais por vaca vira motivo para abandonar o sistema, e a meta de 95% depende do uso.

**Correção.**
- Um **botão físico com LED** em cada posto, à prova d'água. Toque curto: início ou fim. Toque longo: esvaziamento.
- O LED mostra o estado: aguardando, medindo, gravado, erro.
- O celular fica num suporte fixo com carregador. Ele serve para escolher o animal e lançar ração, não para cada evento.
- Lista de próximas vacas na ordem habitual de entrada, para escolher o animal com um toque.

### 11. Situação do animal

**Problema.** A meta de 95% desconta vacas secas ou ausentes, mas o cadastro só prevê data do parto.

**Correção.** Cadastro com situação (lactação, seca, vendida, morta), data de secagem e ausências por turno.
As ordenhas esperadas do dia são calculadas pelas vacas em lactação menos ausências registradas.

### 12. Ração fornecida

**Problema.** A pergunta 2 pede quanto concentrado foi fornecido. Sem método, o campo vira chute.

**Correção.**
- O concentrado é dado com uma medida padrão, como lata ou caneca. Na semana 1, pesar 10 medidas cheias e registrar a média em kg.
- O operador lança número de medidas. O sistema converte para kg.
- Se o operador não alterar, o fornecido assume o programado e fica marcado como **estimado**.
- Repetir a pesagem da medida a cada mês ou quando mudar a ração.
- A balança auxiliar serve para isso. Uma balança de bancada de 30 kg basta.

### 13. Protocolo das 30 comparações

**Problema.** O plano não diz como comparar a balança do posto com a referência.
Pesar o balde cheio, de 90 kg, numa balança de referência antes e depois de cada vaca é inviável na rotina.

**Correção.** Três fases, descritas em `docs/04-validacao.md`:
1. **Bancada**: massas conhecidas sobre a plataforma, antes de ir para a sala.
2. **Sala com vácuo real**: adicionar ao balde, com vácuo e pulsação ligados, galões de água pesados na referência. Simula a condição real sem depender da vaca.
3. **Ordenha real**: amostra menor de vacas pesadas na referência, só para confirmar.

A balança de referência deve ter selo de verificação do Inmetro em dia ou ser conferida com massas conhecidas.

### 14. "Registro válido"

**Problema.** A meta de 95% de registros válidos não define validade.

**Correção.** Um registro de ordenha é válido quando:
- tem animal identificado;
- todas as parciais têm início e fim estáveis;
- a produção está entre 0,3 kg e 40 kg;
- não foi marcado como inválido pelo operador ou pela conferência.

### 15. Alertas entre turnos

**Problema.** Com intervalo desigual entre ordenhas, a ordenha da manhã costuma render mais que a da tarde.
Comparar a ordenha atual com a anterior gera alerta falso duas vezes por dia.

**Correção.** Comparar a vaca com a média dela no mesmo turno nos últimos 7 dias, ou com o total diário.
Exigir pelo menos duas ordenhas seguidas abaixo do limite antes de alertar.

### 16. Sincronização

**Problema.** "Funciona local e sincroniza depois" pode significar duas coisas diferentes. E o servidor não deve ser exposto à internet.

**Correção.** São duas camadas:
1. **Posto para servidor local**: obrigatória desde o posto 1. O ESP32 guarda e reenvia.
2. **Servidor local para nuvem**: opcional, a partir do mês 3. Sempre conexão de saída iniciada pelo servidor local. Nada entra na fazenda vindo da internet.

### 17. Meta de 95% sem etapa

**Problema.** A meta de 30 dias não está ligada a nenhum critério de avanço.

**Correção.** A medição começa na semana 6, com os três postos, e é o critério de passagem para "validar o manejo" no mês 3.

### 18. Visitas a propriedades

**Problema.** "Visitar 3 a 5 propriedades durante o desenvolvimento" não tem prazo e compete com o piloto.

**Correção.** Duas visitas entre as semanas 6 e 9, para observar rotina, e o restante nos meses 3 a 5, já com o sistema para mostrar.

### 19. Taxa do HX711

**Problema.** Na conversa anterior foi sugerido usar o HX711 a 80 amostras por segundo.
A maioria dos módulos vem fixa em 10 amostras por segundo e precisa de alteração na placa. Em 10 amostras por segundo o ruído é menor.

**Correção.** Começar em 10 amostras por segundo, sem modificar o módulo.
A janela de estabilidade dura de 3 a 5 segundos, cobrindo vários ciclos do pulsador, o que já cancela a vibração periódica.
Só mudar para 80 se a bancada mostrar necessidade.

### 20. Capacidade nominal e esvaziamento

**Problema.** Um balde com 70 L de leite pesa perto de 90 kg. Ninguém levanta isso sozinho para despejar.
O plano não diz como o balde é esvaziado, e isso decide o desenho da plataforma.
Encher até a borda também arrisca leite entrando na linha de vácuo.

**Correção.**
- Medir na semana 1 o volume real do balde e até onde ele é enchido na prática.
- Registrar como é feito o esvaziamento: transferência por bomba, despejo, troca de balde.
- Definir um **limite operacional** de enchimento, por exemplo 80% do volume. O painel avisa quando o balde se aproxima dele.
- Se o balde for retirado para despejo, a plataforma precisa de rampa ou guia, e cada retirada abre uma nova parcial.

### 21. Balança de referência sem orçamento

**Problema.** A validação exige "balança de referência conferida", mas o orçamento não tem essa linha.
Ao mesmo tempo, a "balança auxiliar para ração" aparece como opcional.

**Correção.** Uma balança de bancada de 30 kg, com divisão de 5 g ou menor e verificação do Inmetro em dia, faz os dois papéis.
Ela pesa os galões de água da validação e calibra a medida de ração.
A balança de plataforma para conferir o balde inteiro fica condicional, por empréstimo ou aluguel.

### 22. Relógio sem internet

**Problema.** O ESP32 não tem relógio de tempo real. O Raspberry também não.
Se a fazenda não tiver internet, depois de cada queda de energia os dois voltam com a hora errada.
Turno, data da ordenha e alertas dependem da hora.

**Correção.**
- Se não houver internet, o Raspberry ganha um módulo de relógio DS3231 com bateria.
- O servidor local serve a hora na rede pelo protocolo NTP, e os postos sincronizam com ele.
- Cada evento leva também o tempo desde que o posto ligou. Se o posto ainda não tiver hora, o servidor estima o horário pela diferença e marca o evento como hora estimada.
- O identificador do evento não depende da hora. Ver `docs/06-decisoes.md`.

## Pontos a confirmar na semana 1

| Pergunta | Por que importa |
|---|---|
| O bezerro mama antes ou depois da ordenha? | Define se o sistema mede produção ou leite ordenhado |
| Volume real do balde e nível de enchimento usual | Define célula, limite operacional e frequência de esvaziamento |
| Como o balde é esvaziado | Define a mecânica da plataforma |
| O pulsador é pneumático ou elétrico? | Se elétrico, entra na conta da fonte e da interferência |
| Há sinal Wi-Fi na sala de ordenha? | Define se o ponto de acesso entra na etapa 1 |
| Frequência de quedas de energia | Define se o nobreak é obrigatório na etapa 1 |
| Medida usada para o concentrado | Define a calibração da ração |
| Destino de leite descartado e de bezerros | Define a conciliação |
| O laticínio emite ticket de coleta? | Define a referência da conciliação |
| Há internet na fazenda? | Define se o servidor precisa de módulo de relógio |
