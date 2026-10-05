# Protocolo de validação

As planilhas de registro estão em `planilhas/`. Cada fase tem critério de aprovação próprio.

## Balança

### Meta

Erro por ordenha de no máximo **200 g ou 2% da produção, o que for maior**.

O erro de uma ordenha vem de duas leituras, início e fim. Por isso cada leitura isolada precisa ser melhor que a meta.

### Referência

- Balança de bancada de 30 kg, divisão de 5 g ou menor, com verificação do Inmetro em dia.
- Antes de cada dia de teste, conferir a referência com uma massa conhecida e anotar.
- Massas de teste: galões com água, pesados na referência imediatamente antes do uso.

### Fase 1 · Bancada

Local: casa ou oficina, antes de levar o posto para a sala.

| Teste | Como | Critério |
|---|---|---|
| Linearidade | Carregar 0, 5, 10, 20, 40, 60 e 80 kg em degraus, subindo e descendo | Erro em cada ponto até 100 g |
| Carga fora do centro | 20 kg no centro e em cada um dos 4 cantos da plataforma | Diferença entre posições até 100 g |
| Retorno a zero | Carregar 80 kg, retirar, ler após 1 min | Até 50 g |
| Deriva | 40 kg parados por 2 h, uma leitura a cada 10 min | Variação até 50 g |
| Repetibilidade | Colocar e retirar o mesmo galão 10 vezes | Desvio padrão até 30 g |

Os critérios de bancada são metade da meta de campo, porque o campo só piora.
Se a fase 1 falhar, revisar mecânica primeiro e depois considerar trocar o HX711.

### Fase 2 · Sala com vácuo real

Local: sala de ordenha, posto instalado, sem vaca. Esta fase gera as **30 comparações**.

1. Balde vazio na plataforma, tampa conectada, vácuo e pulsação ligados.
2. Mangueiras no ponto fixo, conjunto no gancho. Condição padrão de leitura.
3. Encher um recipiente com água e pesar na referência. Anotar a massa antes.
4. Marcar início no posto.
5. Mergulhar as teteiras na água e deixar o vácuo aspirar uma parte, simulando a ordenha.
6. Retirar o conjunto, drenar o tubo, pendurar no gancho.
7. Marcar fim no posto.
8. Pesar o recipiente de novo na referência. A diferença é a massa transferida.
9. Repetir sem esvaziar o balde. O nível sobe e cobre balde pouco cheio, meio e perto do limite.

Variações obrigatórias dentro das 30 comparações:

- pelo menos 10 com balde abaixo de 25% do limite operacional;
- pelo menos 10 entre 25% e 75%;
- pelo menos 5 acima de 75%;
- pelo menos 5 com retirada e reposição do balde entre comparações;
- transferências entre 3 kg e 20 kg, cobrindo vacas de baixa e alta produção;
- uma sessão de pelo menos 2 h, para ver variação ao longo do tempo.

Erro de cada comparação:

```
erro = (fim no posto − início no posto) − (antes na referência − depois na referência)
```

**Aprovação:**

- pelo menos 28 das 30 comparações dentro da meta;
- nenhuma acima do dobro da meta;
- média dos erros, que é o viés, até 100 g. Se o viés for maior, recalibrar e repetir.

Ao fim, lavar o equipamento pelo procedimento normal da fazenda.

### Fase 3 · Ordenha real

Confirmação com vacas. Só depende de uma balança de plataforma de 150 a 300 kg emprestada ou alugada.

- Colocar o posto inteiro sobre a balança de plataforma.
- Em 10 ordenhas, comparar a produção medida no posto com a diferença lida na plataforma.
- Como a plataforma costuma ter divisão de 20 a 50 g, esta fase confirma a ordem de grandeza. Ela não substitui a fase 2.

Se não houver balança de plataforma disponível, a conciliação diária cumpre esse papel de forma mais grosseira.

### Conciliação com o tanque

- Soma das ordenhas com destino tanque, convertida para litros pela densidade de 1,032 kg/L.
- Comparada com o ticket de coleta do laticínio, ou com a régua do tanque se não houver ticket.
- Diferença acima de 5% gera alerta e investigação.
- Serve para detectar erro grosseiro, como posto descalibrado ou ordenha não registrada. Não valida a meta por vaca.

### Rotina de conferência

| Quando | O quê |
|---|---|
| Toda sessão | O servidor compara a tara do balde vazio com a de referência. Diferença acima de 300 g gera alerta |
| Semanal | Um galão pesado na referência transferido como na fase 2, por posto |
| Mensal ou após manutenção | Fase 2 reduzida, com 5 comparações por posto |

## Uso

### Registro válido

Uma ordenha é válida quando tem animal identificado, todas as parciais têm início e fim estáveis, a produção está entre 0,3 kg e 40 kg e não foi anulada.

### Meta

**95% das ordenhas esperadas com registro válido, durante 30 dias seguidos.**

```
ordenhas esperadas = vacas em lactação em cada turno − ausências registradas
taxa = ordenhas válidas ÷ ordenhas esperadas
```

A contagem começa na semana 6, com os três postos. Ela é o critério de passagem para a fase de manejo.

### Operador sem ajuda

- Toda ajuda remota ou presencial é registrada como ocorrência do tipo ajuda.
- Critério: no máximo uma ajuda por semana, durante 2 semanas seguidas, sem presença do desenvolvedor na sessão.

### Tempo

- Cronometrar 4 sessões na semana 1, sem o sistema.
- Cronometrar 4 sessões na semana 9, com os três postos.
- Registrar em `planilhas/tempos.csv`: duração da sessão, tempo por vaca, tempo de esvaziamento e tempo no celular.
- O sistema não pode acrescentar mais de 10% ao tempo da sessão. Se acrescentar, a causa vai para a revisão semanal.

## Manejo

- Toda intervenção é registrada com animal, data, tipo, descrição, carência e acompanhamento.
- Revisão semanal curta, registrada em `planilhas/revisao_semanal.csv`: o que ajudou, que alerta foi inútil, onde o sistema atrapalhou e o que muda na semana seguinte.
- Fatores que mudam a produção sem relação com o sistema são registrados como ocorrências da fazenda: troca de volumoso, mudança de concentrado, chuva ou calor forte, entrada ou saída de vacas.
- Aumento de produção sozinho não prova efeito do sistema. O que se avalia é se as intervenções foram tomadas mais cedo ou com mais base do que antes.
