# Lista de componentes

A lista completa, com especificação e faixa de preço por item, está em `planilhas/bom.csv`.
Os totais abaixo são gerados por `tools/bom_totais.py` a partir dessa planilha. Ao mudar um preço, rode o script e atualize esta tabela.

Preços são faixas estimadas em reais, sem cotação fechada, com valores de outubro de 2026.

## Totais por etapa

- **E1**: posto 1 no modo coleta por aproximação, mais material de validação. Sem servidor na fazenda.
- **E2**: postos 2 e 3, servidor local, ponto de acesso e painel em tempo real.
- **Mínimo**: só itens obrigatórios, preço mínimo.
- **Máx. obrig.**: só itens obrigatórios, preço máximo. É a faixa provável.
- **Máx. total**: inclui os condicionais no preço máximo. É o pior caso.

<!-- bom:inicio -->
| Etapa | Grupo | Mínimo | Máx. obrig. | Máx. total |
|---|---|---|---|---|
| E1 | infra | R$ 0 | R$ 0 | R$ 280 |
| E1 | posto | R$ 608 | R$ 1.570 | R$ 1.570 |
| E1 | validacao | R$ 240 | R$ 550 | R$ 700 |
| E2 | infra | R$ 395 | R$ 930 | R$ 2.070 |
| E2 | posto | R$ 1.140 | R$ 2.940 | R$ 3.040 |

Com reserva de 20%:

| Etapa | Mínimo | Máx. obrig. | Máx. total |
|---|---|---|---|
| E1 | R$ 1.018 | R$ 2.544 | R$ 3.060 |
| E2 | R$ 1.842 | R$ 4.644 | R$ 6.132 |
| **Total** | R$ 2.860 | R$ 7.188 | R$ 9.192 |
<!-- bom:fim -->

## O que mudou em relação ao plano inicial

| Item | Antes | Agora | Motivo |
|---|---|---|---|
| Célula | 100 a 150 kg | 150 kg mínimo, 200 kg aceitável | Carga estática chega a 99 kg sem contar impacto |
| Batente de sobrecarga | não previsto | obrigatório | Protege a célula ao colocar o balde cheio |
| ESP32 | genérico | com antena externa | Caixa fechada e estrutura metálica atenuam o sinal |
| Botão e LED | não previsto | um por posto | Operador com mãos ocupadas, três vacas ao mesmo tempo |
| Alimentação | "baixa tensão" | fonte única de 12 V e conversor por posto | Sem tomada na área molhada e sem queda de tensão |
| Conector | não previsto | aviação GX16 | Troca rápida do posto e da célula sem abrir a caixa |
| Respiro | não previsto | membrana na caixa | Lavagem e variação de temperatura condensam água dentro |
| Armazenamento | cartão SD | SSD ou cartão de alta durabilidade | Queda de energia corrompe o cartão comum |
| Nobreak | não previsto | condicional na E1 | Depende das quedas observadas na semana 1 |
| Ponto de acesso | não previsto | condicional na E1 | Depende do sinal na sala |
| Relógio do servidor | não previsto | DS3231 condicional na E1 | Sem internet, o servidor perde a hora em cada queda de energia |
| Balança de referência | sem linha de orçamento | bancada 30 kg com verificação | A validação exige uma referência conferida |
| Balança de ração | R$ 150 a 400, opcional | absorvida pela balança de referência | A mesma balança calibra a medida de ração |
| Infraestrutura | toda na etapa 2 | só fonte e cabo na E1; servidor, ponto de acesso e armazenamento na E2 | Modo coleta: o notebook é o servidor e vem até o posto |
| ESP32 do posto 1 | antena externa | DevKit comum, antena na placa | No modo coleta o computador fica a metros do posto |
| Relógio | não previsto | DS3231 obrigatório em cada posto | Sem servidor para dar a hora, o posto precisa do próprio relógio |

## Por que estes componentes

### Célula de carga

- Single point permite carga fora do centro dentro da plataforma declarada, o que é necessário porque o balde nunca fica no mesmo lugar.
- Grau de proteção IP67, porque a sala é lavada com mangueira.
- Não cortar o cabo de fábrica. Se a célula tiver 6 fios, ligar o sense positivo na excitação positiva e o sense negativo na excitação negativa, junto ao HX711.

### Conversor analógico

- HX711 no protótipo por custo e disponibilidade.
- Taxa de 10 amostras/s, como vem de fábrica.
- Montado dentro da caixa, com o cabo da célula entrando direto, sem emenda.
- Plano B se a bancada mostrar ruído ou deriva acima do aceitável: NAU7802 ou ADS1232. O firmware isola a leitura numa função para facilitar a troca.

### ESP32

- Versão WROOM-32U, com conector para antena externa.
- Não usar WROVER: os pinos 16 e 17 são ocupados pela PSRAM.
- Sem RTC. O identificador de cada evento não depende do relógio. Ver `docs/06-decisoes.md`.
- Firmware em ESP-IDF 5.3, sem bibliotecas externas. Ver `firmware/posto-esp32/README.md`.

### Caixa

- IP66, tampa com parafusos, prensa-cabos em todas as entradas, respiro com membrana.
- Montada acima do nível do balde, longe do respingo direto e com entradas de cabo para baixo.
- Antena do lado de fora.

## Ligação elétrica do posto

```
 Fonte 12 V (local seco, circuito com DR 30 mA)
   │  cabo PP 2x1,0 mm²
   ▼
 GX16 alimentação ── fusível 1 A ── buck 12→5 V ──┬── ESP32 5V
                                                  └── HX711 VCC (analógico)
 ESP32 3V3 ─────────────────────────────────────────── HX711 VDD (lógica)
 ESP32 3V3 ─────────────────────────────────────────── DS3231 VCC (SDA 21, SCL 22)
 ESP32 GND ─────────────────────────────────────────── HX711 GND

 Célula ── GX16 célula ── HX711 E+ E- A+ A-  (blindagem no GND do HX711, só nesse lado)
```

| Sinal | Pino do ESP32 | Observação |
|---|---|---|
| HX711 DOUT | GPIO 16 | |
| HX711 SCK | GPIO 17 | |
| Botão | GPIO 25 | Pull-up interno, botão ligado ao GND, capacitor de 100 nF em paralelo |
| LED verde | GPIO 26 | Resistor de 330 Ω |
| LED vermelho | GPIO 27 | Resistor de 330 Ω |
| DS3231 SDA | GPIO 21 | Pull-up interno; o módulo costuma trazer os seus |
| DS3231 SCL | GPIO 22 | |

- Se o módulo HX711 tiver um só pino de alimentação, ligar em 3,3 V. A excitação cai, mas a resolução continua suficiente.
- Evitar os pinos 0, 2, 5, 12 e 15, que interferem na partida do ESP32.
- Os pinos podem ser mudados em `firmware/posto-esp32/main/config.h`.

## Segurança elétrica

- O circuito que alimenta a fonte tem disjuntor e DR de 30 mA.
- A fonte fica em local seco, fora da área de lavagem.
- Toda a estrutura metálica dos postos é ligada ao terra.
- O circuito da fonte é separado do motor da bomba de vácuo. Se não for possível, usar filtro de linha.
- Dentro da sala, só circula 12 V.
