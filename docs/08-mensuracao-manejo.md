# Mensuração de mudanças de manejo

Este documento define como o supervisório registra uma mudança de manejo e mede o efeito dela.
É o núcleo do produto: a balança e o painel existem para responder "a mudança funcionou?".

## A ideia em uma frase

Toda mudança na fazenda é tratada como um experimento: tem data de início, alvo, hipótese e janela de medição. O supervisório mede antes, mede depois, corrige o que não é efeito da mudança e mostra o resultado com a incerteza.

Analogia com software: a mudança de manejo é o *deploy*, o supervisório é a observabilidade, e o lote que não recebeu a mudança é o grupo de controle.

## O que pode ser medido

| Tipo de mudança | Exemplo | Métrica principal | Métrica de custo |
|---|---|---|---|
| Ração | Trocar o concentrado, mudar a quantidade por vaca, mudar o horário | kg de leite por vaca por dia | kg de leite por kg de concentrado, R$ de concentrado por litro |
| Volumoso | Entrar silagem, trocar a palma, mudar o pasto | kg de leite por vaca por dia | R$ por litro, quando houver custo lançado |
| Alocação | Mover vacas para o curral com sombra, separar lote de alta produção | kg de leite por vaca por dia, por lote | Horas de trabalho, quando lançadas |
| Ambiente | Sombra, ventilador, aspersão, horário da ordenha no calor | kg de leite por vaca por dia em função do ITU | Energia e água, quando lançadas |
| Ordenha | Mudar horário, intervalo entre ordenhas, rotina de preparo | kg por ordenha, diferença manhã e tarde | Tempo de sessão |
| Sanitário | Protocolo de mastite, vermifugação | kg de leite por vaca, leite descartado | Custo do tratamento |

O que o sistema não mede e não deve fingir que mede: composição do leite, condição corporal, reprodução. Isso entra como ocorrência, não como métrica.

## O que confunde o resultado

Produção de leite muda sozinha. Quem compara "antes e depois" sem corrigir estas quatro coisas conclui errado:

| Fator | Como age | Como o sistema corrige |
|---|---|---|
| Estágio de lactação | Depois do pico, a vaca cai cerca de 1% a 2% por semana por natureza | Cada vaca é comparada com a própria tendência das semanas anteriores, não com um valor fixo |
| Calor | ITU acima de 68 começa a reduzir ingestão e produção; acima de 72 a queda é clara | ITU é gravado por dia e entra no relatório ao lado do efeito. Mudanças avaliadas em janelas de ITU muito diferentes são marcadas como confundidas |
| Mudanças sobrepostas | Trocar ração e mover lote na mesma semana | O sistema avisa quando duas mudanças ativas atingem as mesmas vacas |
| Vacas que entram e saem | Parto, secagem, venda, doença | Só vacas presentes e em lactação nas duas janelas entram na conta |

A correção mais forte é a mais simples: **aplicar a mudança primeiro em um lote e deixar o outro como controle**. Calor, estágio de lactação e clima atingem os dois lotes. A diferença entre os lotes é o efeito. Isso se chama diferença em diferenças, e é o desenho padrão do sistema.

## Os três desenhos

Do mais fraco ao mais forte. O painel informa qual desenho a mudança permite.

### 1. Antes e depois, rebanho inteiro

Quando a mudança atinge todas as vacas de uma vez.

- Linha de base: média diária de cada vaca nos 14 dias anteriores ao início.
- Adaptação: os primeiros dias após o início são descartados. Padrão de 7 dias; ração pede 14 a 21 dias.
- Janela de efeito: 14 dias após a adaptação.
- Efeito por vaca: média na janela de efeito menos média na linha de base, corrigida pela tendência da vaca.
- Efeito da mudança: média dos efeitos por vaca, com o intervalo de confiança.

**Limite.** Se chover, esfriar ou o pasto brotar na mesma semana, o efeito fica misturado. O relatório mostra o ITU das duas janelas para o produtor julgar.

### 2. Escalonado por lote

Quando a mudança pode começar em um lote e ir para os outros depois. É o desenho recomendado.

- Lote tratado recebe a mudança no dia zero. Lote de controle segue como estava.
- Mesmas janelas do desenho 1, para os dois lotes.
- Efeito = (depois menos antes do tratado) menos (depois menos antes do controle).
- Depois da janela, o controle recebe a mudança também. Nenhuma vaca fica sem a melhoria por mais de um mês.

**Vantagem.** Clima, estágio médio de lactação e qualquer coisa que atinja a fazenda inteira saem da conta.

**Cuidado.** Os lotes precisam ser parecidos em produção e estágio de lactação. O painel mostra a comparação dos lotes antes de começar.

### 3. Cruzado

Quando a mudança é reversível e barata, como horário de ordenha ou suplemento.

- Lote A recebe, lote B não, por 3 semanas. Depois inverte por mais 3 semanas.
- Cada vaca serve de controle dela mesma.
- É o desenho que exige menos vacas para achar um efeito pequeno.

**Limite.** Não serve para mudança com efeito que demora a sumir, como troca de volumoso.

## Quanto dá para detectar

Estimativa com as premissas de medição deste projeto. Os números são para orientar o desenho, não para prometer ao produtor.

| Premissa | Valor | Origem |
|---|---|---|
| Erro de medição por ordenha | até 200 g, 2 ordenhas por dia | Meta da validação |
| Variação natural dia a dia da mesma vaca | 6% a 10% da produção | Ordem de grandeza da literatura, a confirmar nos dados do piloto |
| Produção típica | 8 a 12 kg por vaca por dia | Perfil regional |

| Desenho | Vacas | Dias por janela | Menor efeito que aparece com confiança |
|---|---|---|---|
| Antes e depois, uma vaca | 1 | 14 | Cerca de 8% a 10% |
| Antes e depois, rebanho | 30 | 14 | Cerca de 3% a 4%, se o clima não mudar |
| Escalonado por lote | 15 + 15 | 14 | Cerca de 4% a 5%, com clima corrigido |
| Cruzado | 30 | 21 + 21 | Cerca de 2% a 3% |

Leitura: **efeito de 1% ou 2% não aparece com 30 vacas em 2 semanas**, qualquer que seja o desenho. Mudanças pequenas precisam de janelas longas ou de repetição. O painel diz quando o resultado é "sem diferença detectável", que é diferente de "não funcionou".

Os valores acima serão recalculados com a variabilidade real medida nas primeiras 4 semanas de dados. Esse recálculo é um entregável do mês 3.

## Registro no sistema

Uma mudança tem:

| Campo | Obrigatório | Observação |
|---|---|---|
| Tipo | sim | Ração, volumoso, alocação, ambiente, ordenha, sanitário, outro |
| Alcance | sim | Fazenda, lote ou animal |
| Início | sim | Data |
| Fim | não | Em branco enquanto vigente |
| Título e descrição | sim | O que mudou, em uma frase |
| Hipótese | sim | O que se espera. Exemplo: "+0,5 kg por vaca em 3 semanas" |
| Dias de adaptação | sim | Padrão 7; ração 14 |
| Dias da janela | sim | Padrão 14 |
| Custo por dia | não | Quando houver, o painel mostra retorno sobre o custo |

Regras:

- Mudança registrada no dia em que começa, não depois. O painel tem um botão "registrar mudança de hoje".
- Alocação de vacas em lotes é um registro próprio, com data. Mover vaca de lote sem registrar invalida a análise daquele lote.
- O sistema avisa quando a janela de efeito termina e mostra o resultado na revisão semanal.

## Tempo como métrica

Algumas mudanças valem pelo tempo que devolvem ao produtor, não pelo leite: porções de ração preparadas, dosador, balanceamento das rodadas, horário da ordenha.

- Métrica principal: **troca média por rodada**, em minutos. A duração total depende do número de vacas em lactação, que muda com partos e secagens; a troca não.
- Desenho: antes e depois no nível da fazenda. Calor e lactação mexem pouco no tempo de troca, então o controle por lote é dispensável aqui.
- O sistema mostra a diferença com intervalo de confiança e o ganho por ordenha, que é a diferença vezes o número de rodadas.
- Uma mudança de tempo também pode mexer no leite, por exemplo se a vaca come menos com porções preparadas. O mesmo registro de mudança alimenta `v_efeito_mudanca`, então os dois efeitos são vistos juntos.

## Clima

- Fonte inicial: estação automática do INMET em Morada Nova, código A332, dados horários públicos. Um serviço no servidor local baixa e grava uma vez por dia.
- O ITU é calculado por hora e resumido por dia: médio, máximo e horas acima de 72.
- Limiares usados nos relatórios: 68 começa o desconforto, 72 queda clara, 79 estresse severo. Para vacas mestiças a tolerância é maior, e o próprio piloto vai mostrar a partir de que ITU a produção cai.
- Sensor local de temperatura e umidade no galpão é item condicional da etapa 1. A estação do INMET fica longe e não vê a sombra do curral. Para avaliar mudança de ambiente, o sensor local é necessário.

## Como o resultado aparece

Para cada mudança, um cartão com:

1. Título, tipo, alcance, datas e desenho usado.
2. Efeito em kg por vaca por dia, com intervalo de confiança, e em percentual.
3. Vacas incluídas e excluídas, com motivo.
4. ITU médio e máximo nas duas janelas. Se diferirem muito, aviso de confusão com clima.
5. Estágio médio de lactação nas duas janelas.
6. Quando houver custo: kg de leite a mais por real gasto por dia.
7. Veredicto em linguagem direta: "melhorou", "piorou", "sem diferença detectável", "confundido com clima" ou "aguardando a janela".

## O que o piloto pode provar

Com uma fazenda, três postos e seis meses:

- Que o sistema detecta mudanças de 4% ou mais no rebanho.
- Que o desenho escalonado por lote funciona na rotina da fazenda.
- Qual é a variabilidade real da produção por vaca na região, que é o número que falta para dimensionar os próximos pilotos.

O que o piloto não prova: que a mudança X é boa em geral. Prova que foi boa naquela fazenda, naquela estação. É isso que o produtor precisa saber.

## Sequência na prova de conceito

1. **Semanas 1 a 9**: só medir. Nenhuma mudança proposta. Isso constrói a linha de base e a variabilidade real.
2. **Mês 3**: primeira mudança, escolhida com o produtor, de efeito esperado grande, com desenho escalonado. Candidata natural: quantidade ou tipo de concentrado em um lote.
3. **Mês 4**: segunda mudança, de outra categoria, por exemplo sombra ou horário de ordenha.
4. **Mês 5 e 6**: revisar as duas, recalcular a tabela de detecção com dados reais, documentar o método para o piloto externo.
