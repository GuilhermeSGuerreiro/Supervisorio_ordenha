// Firmware do posto de ordenha · SCARA · ESP-IDF
// Regras de operação: docs/02-operacao.md. Decisões: docs/06-decisoes.md.
//
// Núcleo 1, tarefa "medicao": balança, botão, LED, máquina de estados, gravação na fila.
// Núcleo 0, tarefa "rede": Wi-Fi, hora, envio da fila e do estado.
// Tarefa "console": comandos de instalação pela serial.

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "driver/gpio.h"
#include "driver/uart.h"
#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "estado.h"
#include "evento.h"
#include "fila.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "hx711.h"
#include "janela.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "rede.h"

namespace {

const char* TAG = "posto";

nvs_handle_t nvs = 0;
SemaphoreHandle_t mtx = nullptr;  // protege todo o estado abaixo entre medição e console

Hx711 hx;
Janela<JANELA_AMOSTRAS> janela;
Calibracao cal;

uint32_t boot = 0;
uint32_t seq = 0;
EstadoPosto estado = EstadoPosto::SemBalde;

uint32_t amostras = 0;
uint32_t ultimaAmostraMs = 0;
int32_t ultimoBruto = 0;

struct {
  bool valido = false;
  uint32_t boot = 0;
  uint32_t seq = 0;
  EstadoPosto estadoAnterior = EstadoPosto::SemBalde;
} ultimo;

struct {
  bool ativo = false;
  Transicao t{};
  uint32_t amostraMarca = 0;
  uint32_t desdeMs = 0;
  uint64_t uptimeMs = 0;
  int64_t epochMs = -1;
} pendente;

uint32_t confirmacaoAteMs = 0;
uint32_t recusaAteMs = 0;
bool falhaGravacao = false;

struct Trava {
  Trava() { xSemaphoreTake(mtx, portMAX_DELAY); }
  ~Trava() { xSemaphoreGive(mtx); }
};

uint32_t agoraMs() { return static_cast<uint32_t>(esp_timer_get_time() / 1000); }

// ---------------------------------------------------------------------------
// NVS
// ---------------------------------------------------------------------------

uint32_t lerU32(const char* k, uint32_t padrao) {
  uint32_t v = padrao;
  nvs_get_u32(nvs, k, &v);
  return v;
}

void gravarU32(const char* k, uint32_t v) {
  nvs_set_u32(nvs, k, v);
  nvs_commit(nvs);
}

void lerStr(const char* k, char* dst, size_t n) {
  size_t tam = n;
  if (nvs_get_str(nvs, k, dst, &tam) != ESP_OK) dst[0] = '\0';
}

void salvarEstado() {
  nvs_set_u8(nvs, "estado", static_cast<uint8_t>(estado));
  nvs_set_u8(nvs, "ult_ok", ultimo.valido);
  nvs_set_u32(nvs, "ult_boot", ultimo.boot);
  nvs_set_u32(nvs, "ult_seq", ultimo.seq);
  nvs_set_u8(nvs, "ult_ant", static_cast<uint8_t>(ultimo.estadoAnterior));
  nvs_commit(nvs);
}

void carregar(rede::Config& rc) {
  boot = lerU32("boot", 0) + 1;
  seq = lerU32("seq", 0);

  // Se a NVS foi apagada, os contadores voltaram a zero, mas a fila ainda guarda a maior chave.
  uint32_t fb, fs;
  if (fila::ultimaChave(fb, fs)) {
    if (fb >= boot) boot = fb + 1;
    if (fs > seq) seq = fs;
  }
  gravarU32("boot", boot);
  gravarU32("seq", seq);

  uint8_t u8 = 0;
  nvs_get_u8(nvs, "estado", &u8);
  estado = u8 <= 2 ? static_cast<EstadoPosto>(u8) : EstadoPosto::SemBalde;
  u8 = 0;
  nvs_get_u8(nvs, "ult_ok", &u8);
  ultimo.valido = u8 != 0;
  ultimo.boot = lerU32("ult_boot", 0);
  ultimo.seq = lerU32("ult_seq", 0);
  u8 = 0;
  nvs_get_u8(nvs, "ult_ant", &u8);
  ultimo.estadoAnterior = u8 <= 2 ? static_cast<EstadoPosto>(u8) : EstadoPosto::SemBalde;

  int32_t off = 0;
  nvs_get_i32(nvs, "offset", &off);
  cal.offset = off;
  uint32_t fatorBits = 0;  // float guardado como bits
  nvs_get_u32(nvs, "fator", &fatorBits);
  memcpy(&cal.fator, &fatorBits, sizeof cal.fator);

  lerStr("ssid", rc.ssid, sizeof rc.ssid);
  lerStr("senha", rc.senha, sizeof rc.senha);
  lerStr("servidor", rc.servidor, sizeof rc.servidor);
  lerStr("ntp", rc.ntp, sizeof rc.ntp);
  lerStr("chave", rc.chave, sizeof rc.chave);
}

// ---------------------------------------------------------------------------
// Balança
// ---------------------------------------------------------------------------

void lerBalanca() {
  if (!hx.pronto()) return;
  ultimoBruto = hx.ler();
  janela.adicionar(ultimoBruto);
  amostras++;
  ultimaAmostraMs = agoraMs();
}

bool balancaFalhou() { return agoraMs() - ultimaAmostraMs > SEM_AMOSTRA_FALHA_MS; }

bool estavel() {
  return janela.cheia() && !balancaFalhou() && cal.gramasDesvio(janela.desvioBruto()) <= DESVIO_MAX_G;
}

int32_t massaAtualG() { return cal.gramas(janela.medianaBruta()); }

// ---------------------------------------------------------------------------
// Eventos
// ---------------------------------------------------------------------------

bool gravarEvento(Evento& e) {
  e.boot = boot;
  e.seq = ++seq;
  gravarU32("seq", seq);  // antes da fila: um seq nunca é reutilizado
  if (!fila::gravar(e)) {
    falhaGravacao = true;
    ESP_LOGE(TAG, "falha ao gravar evento na fila");
    return false;
  }
  falhaGravacao = false;
  ESP_LOGI(TAG, "evento %u/%u %s massa=%ld estavel=%u", unsigned(e.boot), unsigned(e.seq), nomeTipo(e.tipo),
           long(e.massaG), unsigned(e.estavel));
  return true;
}

void concluirPendente(bool comEstabilidade) {
  Evento e{};
  e.tipo = pendente.t.tipo;
  e.estavel = comEstabilidade ? 1 : 0;
  if (balancaFalhou() || !cal.valida()) {
    e.massaG = MASSA_AUSENTE;
    e.estavel = 0;
  } else {
    e.bruto = janela.medianaBruta();
    e.massaG = cal.gramas(e.bruto);
    e.desvioG = static_cast<int32_t>(lroundf(cal.gramasDesvio(janela.desvioBruto())));
  }
  e.uptimeMs = pendente.uptimeMs;
  e.epochMs = pendente.epochMs;

  const EstadoPosto anterior = estado;
  pendente.ativo = false;
  if (!gravarEvento(e)) return;

  ultimo.valido = true;
  ultimo.boot = e.boot;
  ultimo.seq = e.seq;
  ultimo.estadoAnterior = anterior;
  estado = pendente.t.proximo;
  salvarEstado();
  confirmacaoAteMs = agoraMs() + 900;
}

void acaoOperador(Acao a) {
  if (pendente.ativo) {
    recusaAteMs = agoraMs() + 1000;
    return;
  }
  const Transicao t = transicao(estado, a);
  if (!t.aceita) {
    ESP_LOGW(TAG, "ação recusada no estado %s", nomeEstado(estado));
    recusaAteMs = agoraMs() + 1000;
    return;
  }
  pendente.ativo = true;
  pendente.t = t;
  pendente.amostraMarca = amostras;
  pendente.desdeMs = agoraMs();
  pendente.uptimeMs = rede::uptimeMs();
  pendente.epochMs = rede::epochMs();
}

void anular() {
  if (pendente.ativo) {  // nada gravado ainda: só cancela
    pendente.ativo = false;
    confirmacaoAteMs = agoraMs() + 900;
    return;
  }
  if (!ultimo.valido) {
    recusaAteMs = agoraMs() + 1000;
    return;
  }
  Evento e{};
  e.tipo = TipoEvento::Anula;
  e.estavel = 1;
  e.massaG = MASSA_AUSENTE;
  e.refBoot = ultimo.boot;
  e.refSeq = ultimo.seq;
  e.uptimeMs = rede::uptimeMs();
  e.epochMs = rede::epochMs();
  if (!gravarEvento(e)) return;
  estado = ultimo.estadoAnterior;
  ultimo.valido = false;  // um nível de anulação
  salvarEstado();
  confirmacaoAteMs = agoraMs() + 900;
}

void verificarPendente() {
  if (!pendente.ativo) return;
  // A janela inteira precisa ser de amostras posteriores ao toque.
  if (amostras - pendente.amostraMarca >= JANELA_AMOSTRAS && estavel()) {
    concluirPendente(true);
  } else if (agoraMs() - pendente.desdeMs > ESPERA_MAX_ESTAVEL_MS) {
    concluirPendente(false);
  }
}

// ---------------------------------------------------------------------------
// Botão
// ---------------------------------------------------------------------------

struct {
  int nivelEstavel = 1;  // pull-up: solto = 1
  int ultimoNivel = 1;
  uint32_t mudouMs = 0;
  uint32_t apertouMs = 0;
} botao;

uint32_t botaoSeguradoMs() { return botao.nivelEstavel ? 0 : agoraMs() - botao.apertouMs; }

void lerBotao() {
  const int nivel = gpio_get_level(static_cast<gpio_num_t>(PINO_BOTAO));
  const uint32_t agora = agoraMs();
  if (nivel != botao.ultimoNivel) {
    botao.ultimoNivel = nivel;
    botao.mudouMs = agora;
    return;
  }
  if (nivel == botao.nivelEstavel || agora - botao.mudouMs < DEBOUNCE_MS) return;

  botao.nivelEstavel = nivel;
  if (!nivel) {
    botao.apertouMs = agora;
    return;
  }
  const uint32_t duracao = agora - botao.apertouMs;
  if (duracao >= TOQUE_ANULA_MS) {
    anular();
  } else if (duracao >= TOQUE_LONGO_MS) {
    acaoOperador(Acao::Balde);
  } else if (duracao <= TOQUE_CURTO_MAX_MS) {
    acaoOperador(Acao::Marca);
  }
  // Entre o curto e o longo: ignorado, evita ação ambígua.
}

// ---------------------------------------------------------------------------
// LED (docs/02-operacao.md)
// ---------------------------------------------------------------------------

void led(bool verde, bool vermelho) {
  gpio_set_level(static_cast<gpio_num_t>(PINO_LED_VERDE), verde);
  gpio_set_level(static_cast<gpio_num_t>(PINO_LED_VERMELHO), vermelho);
}

void atualizarLed() {
  const uint32_t t = agoraMs();
  const bool pisca2Hz = (t / 250) % 2;
  const uint32_t segurado = botaoSeguradoMs();

  if (segurado >= TOQUE_ANULA_MS) return led(false, true);     // soltar agora anula
  if (segurado >= TOQUE_LONGO_MS) return led(true, true);      // soltar agora = balde
  if (t < confirmacaoAteMs) return led((t / 150) % 2, false);  // gravado
  if (t < recusaAteMs) return led(false, pisca2Hz);            // recusado
  if (pendente.ativo) return led(pisca2Hz, pisca2Hz);          // aguardando estabilidade
  if (balancaFalhou() || falhaGravacao || !cal.valida() || massaAtualG() > CARGA_MAXIMA_G ||
      rede::chaveRecusada())
    return led(false, pisca2Hz);  // erro

  bool verde = false;
  switch (estado) {
    case EstadoPosto::SemBalde: verde = (t % 2000) < 100; break;     // piscada curta
    case EstadoPosto::Ocioso: verde = estavel() || pisca2Hz; break;  // fixo quando estável
    case EstadoPosto::Ordenhando: verde = (t / 1000) % 2; break;     // pisca lento
  }
  const bool semRede = !rede::conectado() && (t % 2000) >= 1000 && (t % 2000) < 1100;
  led(verde && !semRede, semRede);
}

// ---------------------------------------------------------------------------
// Tarefa de medição
// ---------------------------------------------------------------------------

void tarefaMedicao(void*) {
  uint32_t proximoStatus = 0;
  for (;;) {
    {
      Trava tr;
      lerBalanca();
      lerBotao();
      verificarPendente();
      atualizarLed();
      if (static_cast<int32_t>(agoraMs() - proximoStatus) >= 0) {
        rede::publicarStatus(massaAtualG(), estavel(), nomeEstado(estado));
        proximoStatus = agoraMs() + 1000;
      }
    }

    // O seq nunca volta atrás em operação normal, então o servidor nunca conhece um seq maior que o do posto.
    // Se conhecer, a flash foi apagada e os contadores recomeçaram: ajusta e reinicia antes de repetir chaves.
    const int64_t sm = rede::seqMaxServidor();
    if (sm > static_cast<int64_t>(seq)) {
      const int64_t bm = rede::bootMaxServidor();
      ESP_LOGW(TAG, "servidor conhece seq %lld, ajustando contadores e reiniciando", static_cast<long long>(sm));
      gravarU32("seq", static_cast<uint32_t>(sm));
      if (bm >= static_cast<int64_t>(boot)) gravarU32("boot", static_cast<uint32_t>(bm));
      esp_restart();
    }

    vTaskDelay(pdMS_TO_TICKS(5));
  }
}

// ---------------------------------------------------------------------------
// Console de instalação
// ---------------------------------------------------------------------------

void ajuda() {
  printf(
      "Comandos:\n"
      "  info                  estado, calibração, fila e rede\n"
      "  ssid <nome>           rede Wi-Fi\n"
      "  senha <senha>         senha do Wi-Fi\n"
      "  servidor <url>        ex.: http://192.168.0.10:3000\n"
      "  ntp <host>            servidor de hora (padrão: host do servidor)\n"
      "  chave <hex>           chave do posto gerada no servidor\n"
      "  tara                  zera com a plataforma vazia\n"
      "  cal <gramas>          calibra com massa conhecida sobre a plataforma\n"
      "  reiniciar             aplica configuração de rede\n");
}

void info() {
  Trava tr;
  printf("versao=%s boot=%u seq=%u estado=%s pendente=%d\n", esp_app_get_description()->version, unsigned(boot),
         unsigned(seq), nomeEstado(estado), pendente.ativo);
  printf("bruto=%ld massa=%ld g desvio=%.1f g estavel=%d falha=%d\n", long(ultimoBruto), long(massaAtualG()),
         cal.gramasDesvio(janela.desvioBruto()), estavel(), balancaFalhou());
  printf("offset=%ld fator=%.4f calibrado=%d\n", long(cal.offset), cal.fator, cal.valida());
  printf("fila=%u wifi=%d rssi=%d hora=%d chave_recusada=%d\n", unsigned(fila::pendentes()), rede::conectado(),
         rede::rssi(), rede::epochMs() > 0, rede::chaveRecusada());
  char ssid[33], servidor[96], chave[65];
  lerStr("ssid", ssid, sizeof ssid);
  lerStr("servidor", servidor, sizeof servidor);
  lerStr("chave", chave, sizeof chave);
  printf("ssid=%s servidor=%s chave=%.4s%s\n", ssid, servidor, chave, chave[0] ? "..." : "(vazia)");
}

void comando(char* linha) {
  while (*linha == ' ') linha++;
  char* arg = strchr(linha, ' ');
  if (arg) {
    *arg++ = '\0';
    while (*arg == ' ') arg++;
  } else {
    arg = linha + strlen(linha);
  }

  if (!strcmp(linha, "info")) return info();
  if (!strcmp(linha, "reiniciar")) return esp_restart();
  if (!strcmp(linha, "ssid") || !strcmp(linha, "senha") || !strcmp(linha, "servidor") || !strcmp(linha, "ntp") ||
      !strcmp(linha, "chave")) {
    if (!strcmp(linha, "chave") && strlen(arg) < 32) return (void)printf("chave curta demais\n");
    nvs_set_str(nvs, linha, arg);
    nvs_commit(nvs);
    printf("%s gravado. Use 'reiniciar' para aplicar.\n", linha);
    return;
  }
  if (!strcmp(linha, "tara") || !strcmp(linha, "cal")) {
    Trava tr;
    // Antes da primeira calibração não há como converter o desvio para gramas: exige só a janela cheia.
    const bool instavel = cal.valida() && cal.gramasDesvio(janela.desvioBruto()) > DESVIO_MAX_G;
    if (!janela.cheia() || balancaFalhou() || instavel) {
      printf("leitura instável ou sem amostras, aguarde e repita\n");
      return;
    }
    const int32_t mediana = janela.medianaBruta();
    if (!strcmp(linha, "tara")) {
      cal.offset = mediana;
      nvs_set_i32(nvs, "offset", cal.offset);
      nvs_commit(nvs);
      printf("tara gravada: offset=%ld\n", long(cal.offset));
      return;
    }
    const float gramas = strtof(arg, nullptr);
    if (gramas <= 0) return (void)printf("uso: cal <gramas>\n");
    const float fator = (mediana - cal.offset) / gramas;
    if (fabsf(fator) < 1e-3f) return (void)printf("sem variação: faça a tara antes e coloque a massa\n");
    cal.fator = fator;
    uint32_t bits;
    memcpy(&bits, &cal.fator, sizeof bits);
    gravarU32("fator", bits);
    printf("calibração gravada: fator=%.4f contagens/g\n", cal.fator);
    return;
  }
  ajuda();
}

void tarefaConsole(void*) {
  uart_driver_install(UART_NUM_0, 512, 0, 0, nullptr, 0);
  char buf[160];
  size_t n = 0;
  for (;;) {
    uint8_t c;
    if (uart_read_bytes(UART_NUM_0, &c, 1, portMAX_DELAY) != 1) continue;
    if (c == '\r' || c == '\n') {
      if (n > 0) {
        buf[n] = '\0';
        printf("\n");
        comando(buf);
        n = 0;
      }
    } else if (n < sizeof buf - 1) {
      buf[n++] = static_cast<char>(c);
      putchar(c);  // eco
      fflush(stdout);
    }
  }
}

void iniciarGpio() {
  gpio_config_t in = {};
  in.pin_bit_mask = 1ULL << PINO_BOTAO;
  in.mode = GPIO_MODE_INPUT;
  in.pull_up_en = GPIO_PULLUP_ENABLE;
  gpio_config(&in);
  gpio_config_t out = {};
  out.pin_bit_mask = (1ULL << PINO_LED_VERDE) | (1ULL << PINO_LED_VERMELHO);
  out.mode = GPIO_MODE_OUTPUT;
  gpio_config(&out);
  led(true, true);
}

}  // namespace

extern "C" void app_main() {
  esp_err_t r = nvs_flash_init();
  if (r == ESP_ERR_NVS_NO_FREE_PAGES || r == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    // Os contadores são recuperados da fila em carregar().
    ESP_ERROR_CHECK(nvs_flash_erase());
    r = nvs_flash_init();
  }
  ESP_ERROR_CHECK(r);
  ESP_ERROR_CHECK(nvs_open("scara", NVS_READWRITE, &nvs));
  mtx = xSemaphoreCreateMutex();

  iniciarGpio();
  if (!fila::iniciar()) falhaGravacao = true;

  rede::Config rc;
  carregar(rc);
  ESP_LOGI(TAG, "SCARA %s boot=%u seq=%u estado=%s", esp_app_get_description()->version, unsigned(boot),
           unsigned(seq), nomeEstado(estado));

  hx.iniciar(static_cast<gpio_num_t>(PINO_HX_DOUT), static_cast<gpio_num_t>(PINO_HX_SCK));
  ultimaAmostraMs = agoraMs();
  if (!cal.valida()) ESP_LOGW(TAG, "balança sem calibração: use tara e cal");

  rede::iniciar(rc, boot);
  xTaskCreatePinnedToCore(tarefaMedicao, "medicao", 6144, nullptr, 5, nullptr, 1);
  xTaskCreatePinnedToCore(tarefaConsole, "console", 4096, nullptr, 2, nullptr, 0);
  ajuda();
}
