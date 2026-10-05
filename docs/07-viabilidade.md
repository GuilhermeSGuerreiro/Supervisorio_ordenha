# Estudo de viabilidade e revisão da execução

Data: outubro de 2026. Revisão do piloto à luz de soluções parecidas já aplicadas, normas de medição de leite e dados do mercado regional.

## Veredicto em uma página

**O projeto é viável e vale seguir, com quatro ajustes de rota.**

| Dimensão | Avaliação | Base |
|---|---|---|
| Técnica | Viável. A eletrônica não é o gargalo, a mecânica é | Orçamento de erro abaixo, firmware compilado, banco testado |
| Operacional | Viável, com risco alto de abandono se o sistema roubar tempo | Revisão de 24 ferramentas de registro em pequenas fazendas, 2024 |
| Econômica para a fazenda | Plausível, mas o ganho vem de decisões sobre vacas, não de economia automática de ração | Literatura de alimentação individual não mostra ganho consistente |
| Econômica para o produto | Viável como negócio pequeno no primeiro ano; depende de canal e de assistência junto | MEI, Centelha, Betânia com 3.500 famílias fornecedoras |
| Mercado | Grande e concentrado perto de você, mas de produtividade baixa | Morada Nova com 117,3 milhões de litros e 41.818 vacas em 2025 |

Os quatro ajustes:

1. **Adotar a norma ICAR como critério mínimo** e manter a meta de 200 g como alvo. A norma internacional para medidores de leite admite erro maior do que o plano exige. Ver seção 3.
2. **Vender medição com acompanhamento, não só o equipamento.** Tudo o que funcionou em pequena fazenda no Brasil, com destaque para o Balde Cheio, juntou registro com visita técnica. Painel sozinho não muda manejo.
3. **Não prometer economia de ração.** A literatura compara ração por produção com ração fixa e não encontra ganho consistente. O que o sistema entrega é saber quanto cada vaca produz e quanto custa, e isso leva a secar, descartar e tratar na hora certa.
4. **Confirmar na semana 1 quantas fazendas da região têm ordenha mecânica em balde.** O mercado endereçável é esse recorte, não o total de produtores. O dado existe no Censo Agropecuário, tabela 6912 do SIDRA, e não foi possível consultá-lo deste ambiente.

## 1. Método e limite deste estudo

As fontes foram localizadas por busca na web. O ambiente onde este estudo foi escrito bloqueia o acesso direto à maioria dos sites, inclusive Embrapa, IBGE, ICAR, SciELO, MDPI e portais de notícias. Por isso, os números abaixo vêm dos resumos de busca, não da leitura integral dos documentos.

Consequência prática: **antes de usar qualquer número deste estudo numa proposta comercial ou num edital, abra a fonte e confira.** A lista de fontes está no fim, com o que cada uma sustenta.

## 2. O que já foi feito de parecido

### 2.1 Protótipos acadêmicos com célula de carga em balde

| Trabalho | O que fizeram | Resultado | O que ensina ao piloto |
|---|---|---|---|
| Kaunkid, Aurasopon e Chantiratikul, *Agriculture*, 2022, Tailândia | Balança com célula de carga e sistema embarcado montados num carrinho de mão para ordenha em balde. Registro em cartão microSD e envio por IoT para planilha Google. Alerta de fim de ordenha pela derivada do peso | Exatidão acima de 99,5% com massas padrão de 1, 5, 20 e 40 kg. Testado com dois conjuntos e 14 vacas | É o trabalho mais próximo do seu. Confirma que célula de carga em balde funciona. Mediu com massas padrão, não com leite em ordenha real, e não relata uso prolongado. O alerta de fim de ordenha pela derivada do peso é uma ideia barata para o módulo 2 |
| *Monitoring System for a Bucket Milking Machine Based on IoT*, 2021 | Monitoramento de parâmetros do balde ao pé por IoT | Resumo não detalhado nas fontes acessíveis | Mostra interesse acadêmico no mesmo problema. Conferir o texto completo |
| *Milk weighing scale based on machine learning*, *Smart Agricultural Technology*, março de 2024 | Sensor de fluxo em sala de ordenha de baixo custo, com câmeras para rotular o peso real, e modelo de regressão para prever o peso do leite | Erro percentual médio absoluto mínimo de 10,26% | Caminho mais complexo e menos preciso que pesar o balde. Reforça a escolha pela balança |
| Revisão de ferramentas de registro para pequenas fazendas leiteiras em países em desenvolvimento, *Tropical Animal Health and Production*, 2024 | 24 ferramentas em 21 artigos | 15 de 24 são aplicativos de celular. Quase todas dependem de digitação manual. Só uma registrava produção individual automaticamente. A maioria nunca saiu do protótipo | Seu diferencial é exatamente o que falta na literatura: entrada automática. O risco também está descrito: protótipo que não vira operação |

### 2.2 Medidores comerciais

| Produto | Tipo | Preço encontrado | Limitação para o seu caso |
|---|---|---|---|
| Waikato Mark V, 30 kg | Medidor proporcional, leitura manual, aprovado ICAR | R$ 4.321,84 por unidade | Um por posto, leitura visual e anotação manual. Usado em dia de controle leiteiro, não em toda ordenha |
| Milk Meter nacional, 42 kg | Medidor proporcional para controle leiteiro, adaptável a balde ao pé | R$ 895,50 | Mesma limitação: leitura e anotação manuais |
| DeLaval MM27BC | Medidor eletrônico aprovado ICAR | Não encontrado | Feito para sala canalizada |

Leitura: o produto comercial mais barato que resolve o mesmo problema custa perto do seu posto inteiro e ainda exige anotar à mão. O Waikato custa mais que um posto seu e também é manual. O seu posto não precisa ser mais exato que eles, precisa ser automático e funcionar em toda ordenha.

### 2.3 Alertas por queda de produção em sistemas comerciais

Estudo em rebanhos da Baviera avaliou a detecção de mastite clínica por robôs de ordenha. Os alertas de produção usam desvio diário de 4 kg ou 20%, ou queda acima de 7 kg. A sensibilidade ficou entre 31% e 78% e a especificidade entre 79% e 97%, conforme o fabricante, e isso com condutividade elétrica além do peso.

O que isso significa para o piloto: um alerta só por queda de produção vai perder casos e vai dar alarme falso. A regra do plano, duas ordenhas seguidas abaixo de 80% da média da própria vaca no mesmo turno, está na mesma faixa do que os fabricantes usam. Não venda o alerta como diagnóstico. Venda como "olhe esta vaca".

### 2.4 O que funcionou em pequena fazenda no Brasil

**Balde Cheio, Embrapa.** Programa desde 1998. Relatório de impacto citado pela Embrapa em 2023: mais de 3 mil propriedades, 247 técnicos, 375 municípios em 18 estados, retorno de R$ 44,41 para cada real investido. Cerca de 75% dos participantes produzem mais de 200 litros por dia, contra uma média nacional abaixo de 100. A metodologia exige do produtor anotações diárias de clima e finanças e **controle leiteiro pelo menos mensal**, com visita técnica mensal obrigatória.

Duas conclusões para o seu produto:

- O ganho vem da combinação de registro com acompanhamento técnico. É isso que o seu "assistência próxima" precisa significar na prática.
- O Balde Cheio pede controle leiteiro mensal. Você entrega controle diário automático. Isso é mais do que o programa exige, e o argumento de venda é poder pegar a mudança da vaca na semana em que acontece, e não no mês seguinte.

**Controle leiteiro reduzido, Embrapa.** Publicação que propõe esquema reduzido de pesagem para fazendas de economia familiar, e análise econômica na *Arquivo Brasileiro de Medicina Veterinária e Zootecnia*, 2005, mostrando que o esquema mensal tradicional tem o maior custo mensal e a pior relação custo-receita entre os esquemas comparados. Ou seja: o custo de pesar à mão é o motivo pelo qual pequena fazenda não pesa. Automação ataca exatamente esse custo.

**GisLeite, Embrapa.** Gratuito, web e Android, gestão zootécnica e econômica, listas de intervenção e relatórios. Não mede nada. Precisa de digitação. É o concorrente do seu painel, não da sua balança. Vale avaliar exportar seus dados num formato que o GisLeite importe, em vez de competir com ele.

## 3. Viabilidade técnica

### 3.1 A exigência de exatidão do plano é mais dura que a norma internacional

A ICAR, organismo internacional de registro animal, define em sua Seção 11 os limites para medidores de leite de vaca:

| Produção por ordenha | Viés máximo | Desvio padrão máximo |
|---|---|---|
| 2 a 10 kg | 0,2 kg | 0,5 kg |
| Acima de 10 kg | 2% | 5% |

O plano exige erro por ordenha de 200 g ou 2%. Isso equivale ao viés da ICAR, mas é bem mais apertado que o desvio padrão admitido, de 500 g para vacas de até 10 kg.

**Recomendação.** Dois níveis em `docs/04-validacao.md`:

- **Mínimo aceitável**: critérios da ICAR acima. Sem isso, não avança.
- **Meta**: 28 de 30 comparações dentro de 200 g ou 2%, como já está.

Assim um resultado de 24 em 30 não derruba a etapa se o viés e o desvio padrão estiverem dentro da norma. A ICAR usa pesagem como método de referência, o que valida a sua fase 2 com galões pesados.

### 3.2 Orçamento de erro: a eletrônica sobra, a mecânica decide

Célula single point de 150 kg, classe C3, com os números de uma ficha típica, e HX711 com os números da própria ficha:

| Fonte de erro | Especificação | Efeito na leitura |
|---|---|---|
| Erro combinado da célula | 0,023% do fundo de escala | 35 g |
| Deriva de zero com temperatura | 0,017% do fundo de escala a cada 10 °C | 25 g a cada 10 °C. A tara por sessão cancela quase tudo |
| Ruído do HX711 a 10 amostras/s | 50 nV eficazes | Menos de 1 g, com célula de 2 mV/V e 5 V de excitação |
| Deriva de zero do HX711 | 6 nV/°C | Menos de 0,1 g por °C |
| Deriva de ganho do HX711 | 5 ppm/°C | Cerca de 0,4 g por °C com 80 kg na plataforma |

Soma honesta do que vem da eletrônica e da célula: abaixo de 100 g em condição controlada. Sobra margem para a meta de 200 g.

O que não está nessa tabela e é o risco real: força da mangueira, carga fora do centro, vibração do pulsador, vaca encostando, leite parado no tubo. A literatura sobre pesagem dinâmica confirma: o sinal precisa assentar antes da leitura, e leituras instáveis devem ser descartadas. É o que o firmware faz. O mesmo trabalho tailandês montou a balança num carrinho, longe da vaca, o que elimina esses problemas. Você escolheu medir no posto, que é mais útil e mais difícil. A fase 2 da validação, com vácuo e pulsação reais, existe para medir esse risco antes de apostar nos outros dois postos.

### 3.3 Estado do código

- Firmware em ESP-IDF 5.3.6 compila sem avisos. Fila na flash, máquina de estados e janela de estabilidade testadas no PC.
- Banco PostgreSQL com 13 cenários passando, incluindo reenvio sem duplicar, esvaziamento no meio da vaca e permissões.
- O que falta é o que só o campo dá: calibração real, comportamento com vácuo e uso pelo operador.

### 3.4 Pontos técnicos a vigiar

- **Umidade e amônia.** Nenhum trabalho encontrado relata uso de HX711 por meses em sala de ordenha. Caixa IP66 com respiro e inspeção mensal da célula.
- **Energia e hora.** Já tratados na revisão: nobreak condicional, relógio no servidor.
- **Wi-Fi na sala.** Estrutura metálica e paredes atenuam. Antena externa já está na lista.

## 4. Viabilidade operacional

### 4.1 Tempo

Referências de rotina: 7 a 8 minutos por vaca e 15 a 20 vacas por hora por ordenhador em balde ao pé com duas unidades. Com três unidades e três vacas comendo ao mesmo tempo, o operador já está no limite de atenção.

O sistema acrescenta por vaca: dois toques no botão e, quando der, um toque no celular para escolher a vaca. Estimativa de 10 a 15 segundos por vaca, ou 2% a 3% do tempo. A meta do plano, não acrescentar mais de 10%, é folgada. O risco não é o tempo médio. É o toque esquecido, que gera pendência e trabalho depois.

### 4.2 Barreiras de adoção documentadas

A revisão de 2024 lista as barreiras em pequenas fazendas: tempo de digitação, volume de dados a inserir, baixa familiaridade, falta de estímulo, conectividade. Como o desenho atual responde a cada uma:

| Barreira | Resposta no projeto |
|---|---|
| Tempo de digitação | Botão físico e entrada automática. O celular é opcional por vaca |
| Volume de dados | Só animal, ração quando diferente do programado e ocorrência quando houver |
| Familiaridade | Lista de próximas vacas na ordem de entrada, LED com três estados que importam |
| Estímulo | Revisão semanal curta com o operador. Alerta que não serve é desligado |
| Conectividade | Servidor local, posto guarda e reenvia, nuvem opcional |

O que a revisão não resolve e o piloto precisa provar: o operador seguir usando quando você não está lá. Por isso o critério "no máximo uma ajuda por semana durante duas semanas" é o critério mais importante do piloto inteiro.

### 4.3 Riscos de execução do plano

| Risco | Probabilidade | Efeito | Mitigação |
|---|---|---|---|
| Prazo de entrega de célula e caixa atrasar a semana 3 | Alta | Desliza o cronograma | Comprar na semana 1, antes de fechar o desenho mecânico |
| Mecânica mal feita arruinar a medição | Média | Repetir as semanas 3 a 5 | Fase 1 em bancada antes de ir para a sala; batente e ponto fixo da mangueira |
| Operador abandonar o celular | Alta | Ordenhas sem animal | Botão resolve a medição; associação pela ordem de entrada resolve a maioria depois |
| Você ser o único desenvolvedor, em tempo parcial | Certa | Qualquer imprevisto pessoal para o projeto | Documentação já está no repositório; critérios de etapa evitam avançar sem base |
| Aumento de leite ser atribuído ao sistema sem prova | Média | Autoengano e proposta comercial frágil | Já previsto: comparar intervenções, não litros |

## 5. Viabilidade econômica

### 5.1 Para a fazenda

Cenário de referência, parecido com o produtor de Morada Nova citado pela imprensa com 36 vacas e quase 400 litros por dia:

| Item | Valor | Base |
|---|---|---|
| Produção | 300 a 400 L/dia | Perfil regional |
| Preço ao produtor | R$ 2,50/L | Acordo Faec e Alvoar, abril de 2026 |
| Receita | R$ 22 mil a 30 mil por mês | Cálculo |
| Concentrado | Cerca de 40% do custo de produção, regra de 1 kg para 3 L | Embrapa Gado de Leite |
| Gasto com concentrado | 100 a 130 kg/dia, R$ 6 mil a 10 mil por mês conforme o preço do quilo | Cálculo, preço do concentrado a confirmar na região |

Onde o sistema pode gerar dinheiro, em ordem de confiança:

1. **Decisões sobre vacas**: secar, descartar, separar para tratamento. É o benefício clássico do controle leiteiro, reconhecido pela Embrapa. Com 30 a 40 vacas, uma decisão certa por mês já paga o sistema.
2. **Pegar queda cedo.** Com a sensibilidade que a literatura mostra, você pega parte dos casos, não todos. Mesmo assim, antecipar o tratamento de uma mastite clínica evita perda de produção e de leite descartado.
3. **Ração.** A literatura compara alimentação individual por produção com quantidade fixa, com o mesmo total, e não encontra ganho consistente em produção nem em lucro. O que o seu sistema permite não é "dar ração certa e produzir mais". É **saber quanto se gasta por litro produzido e parar de dar concentrado caro a vaca que não responde**. Isso é redução de custo em casos específicos, não um percentual garantido.

Estimativa conservadora: ganho de 2% a 4% na margem, pela soma dos três itens. Em uma fazenda de R$ 25 mil mensais de receita e margem apertada, isso é R$ 300 a 700 por mês. Um kit de 3 postos no custo do piloto, R$ 4 mil a 7 mil, se paga em 1 a 2 anos. **Esse número é uma hipótese a validar nos meses 3 e 4, não um dado.**

Comparação com a alternativa mais barata: uma balança de bancada de R$ 200 e um caderno fazem controle leiteiro mensal. O seu produto só vence isso se for automático, diário e sem anotação. Qualquer passo manual a mais aproxima o seu produto do caderno.

### 5.2 Para o produto

| Fator | Situação | Implicação |
|---|---|---|
| MEI | Limite de R$ 81 mil por ano em 2026. Projeto de Lei Complementar 186/26 propõe R$ 110 mil em 2027 e R$ 140 mil em 2028, ainda sem aprovação | Comporta 15 a 20 kits por ano a R$ 4 mil a 5 mil. Suficiente para 2027. Planejar troca de regime se passar disso |
| Centelha Ceará | Terceira edição teve 1.139 inscrições no estado. Subvenção na faixa de R$ 50 mil | Encaixa no mês 6, com piloto externo em andamento como diferencial |
| StartupCE 2026 | Edital do Sebrae de 7 de julho a 14 de agosto de 2026, 60 startups | Esta edição já fechou. Mirar a de 2027 com dados do piloto |
| Anatel | Módulos ESP32 da Espressif têm homologação. Produto que usa módulo homologado sem alterar os parâmetros de rádio pode usar a homologação do módulo, com etiqueta | Usar módulo homologado, antena dentro do que o certificado do módulo permite. Confirmar as condições exatas antes de vender |
| Inmetro | Fora do escopo se vendido como medidor para gestão | Nunca chamar de balança nem usar para pagamento de leite |

### 5.3 Mercado

| Dado | Valor | Fonte |
|---|---|---|
| Produção de Morada Nova em 2025 | 117,3 milhões de litros, alta de 7,8% | IBGE PPM 2025 |
| Vacas ordenhadas em Morada Nova | 41.818 em 2025, contra 42,6 mil em 2024 | IBGE PPM 2025 |
| Produção por vaca em Morada Nova | Cerca de 2.800 L/ano, perto de 7,7 L/dia | Cálculo com os dois dados acima |
| Produtividade média do Ceará | 1.655 L/vaca/ano em 2024 | SDE Ceará, Cadeia do Leite 2025 |
| Produção do Ceará em 2025 | 1,29 bilhão de litros, segundo maior do Nordeste | IBGE PPM 2025 |
| Propriedades com leite no Ceará | Mais de 74 mil, maioria pequenos produtores | Governo do Ceará, 2020 |
| Betânia em Morada Nova | Fábrica de leite em pó para até 200 mil L/dia, recebe cerca de 40% do leite do estado, mais de 3.500 famílias fornecedoras no Nordeste | Imprensa regional |
| Quixeramobim e Iguatu | 80,1 e 59,0 milhões de litros em 2025 | IBGE PPM 2025 |

Leitura:

- Morada Nova produz mais com menos vacas, sinal de que uma parte dos produtores está investindo em manejo e genética. Esse é o seu cliente inicial.
- A produtividade média baixa diz que a maioria das fazendas é pequena e de baixa tecnologia. Muitas ordenham à mão. O seu mercado é o recorte com ordenha mecânica em balde, e esse número precisa ser levantado.
- O laticínio é um canal. Betânia, Alvoar e a Faec têm interesse em volume e qualidade, e programas de assistência ao fornecedor são comuns no setor. Um piloto com dados sólidos é a porta de entrada para oferecer o kit a grupos de fornecedores.
- Programa estadual de fertilização in vitro e investimento em genética, citados pela Faec, aumentam a necessidade de medir: quem investe em genética quer saber se a vaca nova produz mais.

## 6. Lacunas a fechar

| Lacuna | Como fechar | Quando |
|---|---|---|
| Quantas fazendas da região têm ordenha mecânica em balde | SIDRA, Censo Agropecuário 2017, tabela 6912, filtrar Morada Nova e vizinhos | Semana 1 |
| Texto completo do artigo tailandês de 2022 | Baixar o PDF em MDPI, ler desenho mecânico e problemas relatados | Semana 1 |
| Texto completo da Seção 11 da ICAR | Baixar em icar.org e copiar os limites para `docs/04-validacao.md` | Semana 1 |
| Controle leiteiro reduzido da Embrapa | Baixar na Infoteca e verificar se o esquema pode ser oferecido como relatório do sistema | Semana 2 |
| Cadeia do Leite 2025 da SDE Ceará | Baixar o PDF e extrair estrutura por tamanho de produtor | Semana 2 |
| Preço do concentrado na região | Cotação em duas lojas de Morada Nova | Semana 1 |
| Condições exatas da Anatel para produto com módulo homologado | Ler o ato vigente ou consultar um organismo certificador | Mês 5 |

## 7. O que muda no plano

| Item | Antes | Agora |
|---|---|---|
| Critério da balança | 28 de 30 dentro de 200 g ou 2% | Mínimo: limites da ICAR. Meta: 28 de 30 dentro de 200 g ou 2% |
| Produto | Equipamento com painel | Equipamento com acompanhamento. Revisão semanal no piloto vira visita mensal no produto, no modelo do Balde Cheio |
| Argumento de ração | "Quanto concentrado foi fornecido" | Mantido, mas apresentado como custo por litro e vaca que não responde, nunca como economia garantida |
| Mercado | Produtores de Morada Nova e região | Produtores com ordenha mecânica em balde, número a levantar |
| Painel | Concorrente do GisLeite | Complementar: exportar em formato que o GisLeite aceite |
| Alerta | Queda de produção | "Olhe esta vaca", com sensibilidade e alarme falso declarados ao produtor |

## Fontes

Consultadas por busca. Conferir cada uma antes de citar.

Normas e medição:
- ICAR, Seção 11, Guidelines for Testing, Approval and Checking of Milk Recording Devices: https://www.icar.org/Guidelines/11-Milk-Recording-Devices.pdf
- Ficha do HX711, Avia Semiconductor: https://cdn.sparkfun.com/datasheets/Sensors/ForceFlex/hx711_english.pdf
- Ficha da célula Zemic L6E3, classe C3: https://www.zemiceurope.com/media/Documentation/L6E3_Datasheet.pdf
- Ficha da célula Flintec PC46: https://res.cloudinary.com/flintec/image/upload/v1705853632/strapiDev/pc46_datasheet_en_fc2b252a46.pdf

Trabalhos parecidos:
- Kaunkid, Aurasopon, Chantiratikul. Automatic Milk Quantity Recording System for Small-Scale Dairy Farms Based on Internet of Things. Agriculture, 2022: https://doi.org/10.3390/agriculture12111877
- Monitoring System For A Bucket Milking Machine Based On IoT, 2021: https://www.researchgate.net/publication/354843038
- Milk weighing scale based on machine learning. Smart Agricultural Technology, 2024: https://www.sciencedirect.com/science/article/pii/S2772375524000224
- A review of on-farm recording tools for smallholder dairy farming in developing countries. Tropical Animal Health and Production, 2024: https://link.springer.com/article/10.1007/s11250-024-04024-9
- Sensitivity and Specificity for the Detection of Clinical Mastitis by Automatic Milking Systems in Bavarian Dairy Herds: https://pmc.ncbi.nlm.nih.gov/articles/PMC9405299/
- Individualised feeding of concentrate supplement according to milk yield did not increase milk production: https://www.tandfonline.com/doi/full/10.1080/00288233.2024.2401451
- Effect of concentrate feeding method on the performance of dairy cows. Journal of Dairy Science, 2016: https://www.sciencedirect.com/science/article/pii/S0022030216000564

Manejo e economia no Brasil:
- Embrapa. Balde Cheio reverte para a sociedade 44 reais para cada real investido: https://www.embrapa.br/en/busca-de-noticias/-/noticia/85058476/balde-cheio-reverte-para-a-sociedade-44-reais-para-cada-real-investido
- Embrapa. Metodologia do Programa Balde Cheio, 2021: https://www.alice.cnptia.embrapa.br/alice/bitstream/doc/1140147/1/PL-BALDE-CHEIO-cap2-2021.pdf
- Embrapa. Controle Leiteiro Reduzido para Propriedades Leiteiras de Economia Familiar: https://www.infoteca.cnptia.embrapa.br/infoteca/bitstream/doc/1060088/1/26232.pdf
- Análise econômica de esquemas alternativos de controle leiteiro. Arq. Bras. Med. Vet. Zootec., 2005: https://scielo.br/scielo.php?pid=S0102-09352005000100012&script=sci_arttext
- Embrapa. Distribuição e custos da produção de leite, Anuário Leite: https://www.infoteca.cnptia.embrapa.br/infoteca/bitstream/doc/1134836/1/Distribuicao-producao-leite.pdf
- Embrapa. GisLeite: https://www.embrapa.br/en/busca-de-noticias/-/noticia/50226113/aplicativo-auxilia-no-controle-de-desempenho-do-rebanho-leiteiro

Mercado e região:
- Diário do Nordeste. Ceará ultrapassa Bahia e se torna segundo maior produtor de leite do Nordeste, setembro de 2026: https://diariodonordeste.verdesmares.com.br/negocios/agro/ceara-ultrapassa-bahia-e-se-torna-segundo-maior-produtor-de-leite-do-nordeste-1.3794922
- SDE Ceará. Cadeia do Leite 2025: https://www.sde.ce.gov.br/wp-content/uploads/sites/15/2025/11/CADEIA_DO_LEITE_-_2025-7.pdf
- O Povo. Produtor de leite do Ceará receberá R$ 0,10 a mais, abril de 2026: https://mais.opovo.com.br/jornal/economia/2026/04/01/produtor-de-leite-do-ceara-recebera-rs-010-a-mais-ao-vender-para-a-industria.html
- Governo do Ceará. Pecuária de leite acumula crescimento de quase 63%, 2020: https://www.ceara.gov.br/2020/08/19/pecuaria-de-leite-acumula-crescimento-de-quase-63-no-ceara/
- IBGE SIDRA, tabela 6912, Censo Agropecuário 2017: https://sidra.ibge.gov.br/tabela/6912

Concorrentes:
- Waikato Mark V 30 kg: https://www.ruralban.com/ordenhadeira-mecanica/acessorios/medidor-de-leite-waikato-mark-v-30-kg-original
- Milk Meter nacional 42 kg: https://www.agropeperi.com.br/medidor-de-leite-nacional-milk-meter-42-kg-p-ordenha-com-suporte
- DeLaval MM27BC2: https://www.milkpoint.com.br/canais-empresariais/delaval/medidor-de-leite-delaval-mm27bc2-228599/

Regulação e fomento:
- Limite do MEI em 2026 e PLP 186/26: https://www.infinitepay.io/blog/limite-faturamento-mei-2026
- Módulos Espressif homologados na Anatel: https://blog.macnicadhw.com.br/componentes-eletronicos/modulos-espressif-homologados-anatel/
- Programa Centelha Ceará: https://www.ceara.gov.br/2026/01/14/ceara-e-um-dos-estados-com-mais-inscricoes-de-ideias-no-programa-centelha/
- StartupCE 2026, Sebrae: https://sebrae.com.br/content/dam/portal-sebrae/ce/midias/documentos/pdfs/editais/Edital%20StartupCE%202026.pdf
