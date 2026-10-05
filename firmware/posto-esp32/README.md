# Firmware do posto

ESP32 com HX711, botão e LED. ESP-IDF 5.3, sem componentes externos.
Regras de operação em `docs/02-operacao.md`. Decisões em `docs/06-decisoes.md`.

## Estrutura

| Arquivo | Conteúdo |
|---|---|
| `main/config.h` | Pinos e parâmetros de estabilidade, botão e rede |
| `main/estado.h` | Máquina de estados do posto, código puro |
| `main/janela.h` | Janela de estabilidade e calibração, código puro |
| `main/fila_nucleo.h` | Fila circular na flash, código puro |
| `main/fila.cpp` | Ligação da fila com a partição `fila` |
| `main/hx711.cpp` | Driver do HX711 |
| `main/coleta.cpp` | Modo coleta: ponto de acesso próprio e servidor HTTP que entrega a fila ao notebook |
| `main/rtc.cpp` | Relógio DS3231 por I2C |
| `main/rede.cpp` | Modo servidor: Wi-Fi, hora por NTP e envio ao servidor local, no núcleo 0 |
| `main/main.cpp` | Medição, botão, LED e console, medição no núcleo 1 |
| `partitions.csv` | Tabela de partições com a fila de 256 KB |
| `test/test_nativo.cpp` | Testes das partes puras, rodam no PC |

## Compilar e gravar

Com o ESP-IDF 5.3 instalado e ativado:

```
cd firmware/posto-esp32
idf.py set-target esp32
idf.py build
idf.py -p /dev/ttyUSB0 erase-flash flash monitor
```

Na primeira gravação de um posto novo, use `erase-flash` para a partição da fila começar limpa.
Nas atualizações seguintes, grave só com `flash`, sem apagar, para não perder eventos pendentes.

## Testes no PC

```
g++ -std=c++17 -Wall -Wextra -Imain test/test_nativo.cpp -o /tmp/teste_posto && /tmp/teste_posto
```

Cobrem a máquina de estados, a janela de estabilidade, a calibração e a fila.
A fila é testada com uma flash simulada que respeita as regras da memória NOR, inclusive queda de energia no meio de uma gravação e de uma confirmação.

## Dois modos

| Modo | Quando | Como liga |
|---|---|---|
| `coleta` | Etapa 1. O posto cria a rede `SCARA-POSTO-n` e espera o computador vir buscar os dados | Padrão |
| `servidor` | Etapa 2. O posto entra na rede da fazenda e envia ao servidor local em tempo real | `modo servidor` na serial e `reiniciar` |

No modo coleta, o posto responde em `http://192.168.4.1` com o cabeçalho `X-Chave` igual à chave do posto:

| Chamada | Efeito |
|---|---|
| `GET /info` | Versão, boot, pendentes, hora, leitura atual |
| `GET /eventos?max=200` | Eventos pendentes mais antigos, no formato que o servidor ingere |
| `POST /confirmar {"boot","seq","boot_max","seq_max"}` | Marca como confirmados até boot e seq; os máximos vêm do banco |
| `POST /hora {"epoch_ms"}` | Acerta o relógio do sistema e grava no DS3231 |

`tools/coletar.py` faz a sequência completa.

## Instalação de um posto

1. No servidor, gerar a chave do posto:

   ```sql
   select scara.nova_chave_posto('<id do posto>');
   ```

2. No monitor serial, gravar a configuração e reiniciar. Modo coleta, etapa 1:

   ```
   posto 1
   ap_senha <senha forte do ponto de acesso>
   chave <chave gerada no passo 1>
   hora <segundos desde 1970, UTC>
   reiniciar
   ```

   Modo servidor, etapa 2:

   ```
   modo servidor
   ssid NomeDaRede
   senha SenhaForteDaRede
   servidor http://192.168.0.10:3000
   chave <chave gerada no passo 1>
   reiniciar
   ```

3. Calibrar com a plataforma montada no lugar definitivo:

   ```
   tara
   cal 20000
   info
   ```

   `tara` com a plataforma vazia. `cal` com uma massa conhecida sobre ela, em gramas, pesada na balança de referência.
   Use uma massa de pelo menos 20 kg. Repita a fase 1 da validação depois de calibrar.

4. Conferir com `info`: Wi-Fi conectado, hora sincronizada, fila zerada, balança estável.

## Comandos da serial

| Comando | Efeito |
|---|---|
| `info` | Estado, leitura, calibração, fila e rede |
| `ssid`, `senha`, `servidor`, `ntp`, `chave`, `ap_senha` | Grava a configuração na NVS. Vale após `reiniciar` |
| `modo coleta` ou `modo servidor` | Escolhe o modo. Vale após `reiniciar` |
| `posto <n>` | Número do posto, usado no nome da rede |
| `hora <epoch>` | Acerta o relógio e grava no DS3231 |
| `tara` | Zera com a plataforma vazia |
| `cal <gramas>` | Calibra com massa conhecida |
| `reiniciar` | Reinicia o posto |

Credenciais ficam só na NVS do ESP32, nunca no código nem no repositório.

## Segurança e robustez

- Ponto de acesso com WPA2 e senha própria. Trocar a senha padrão na instalação.
- As chamadas HTTP exigem a chave do posto no cabeçalho.
- Wi-Fi exige WPA2 ou superior no modo servidor.
- Watchdog de tarefas reinicia o posto se algo travar.
- Detecção de queda de tensão ligada.
- O estado do posto e os contadores sobrevivem a reinício.
- Eventos ficam na flash até o servidor confirmar.
- Envio sem TLS, só em rede local. Ver a decisão D10.
