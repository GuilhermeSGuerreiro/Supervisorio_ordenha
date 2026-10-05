#include "rede.h"

#include <string.h>
#include <sys/time.h>

#include <atomic>

#include "cJSON.h"
#include "config.h"
#include "esp_app_desc.h"
#include "esp_event.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "evento.h"
#include "fila.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

namespace rede {
namespace {

const char* TAG = "rede";

Config cfg;
uint32_t bootAtual = 0;
char hostNtp[96] = "";

std::atomic<bool> ativo_{false};
std::atomic<bool> conectado_{false};
std::atomic<bool> recusada_{false};
std::atomic<int64_t> bootMax_{-1};
std::atomic<int64_t> seqMax_{-1};

portMUX_TYPE trava = portMUX_INITIALIZER_UNLOCKED;
struct {
  int32_t massaG = 0;
  bool estavel = false;
  const char* estado = "?";
} status;

enum class Resultado { Ok, Falha, Recusada };

void aoEvento(void*, esp_event_base_t base, int32_t id, void*) {
  if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
    esp_wifi_connect();
  } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
    conectado_ = false;  // a tarefa tenta de novo com intervalo
  } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
    conectado_ = true;
    ESP_LOGI(TAG, "conectado");
  }
}

void extrairHost(const char* url, char* dst, size_t n) {
  const char* p = strstr(url, "://");
  p = p ? p + 3 : url;
  size_t i = 0;
  while (p[i] && p[i] != ':' && p[i] != '/' && i < n - 1) {
    dst[i] = p[i];
    i++;
  }
  dst[i] = '\0';
}

// POST JSON. Devolve o código HTTP ou -1, e o corpo da resposta em `resp`.
int post(const char* caminho, const char* corpo, char* resp, size_t respMax) {
  char url[160];
  snprintf(url, sizeof url, "%s%s", cfg.servidor, caminho);
  esp_http_client_config_t c = {};
  c.url = url;
  c.method = HTTP_METHOD_POST;
  c.timeout_ms = TIMEOUT_HTTP_MS;
  esp_http_client_handle_t h = esp_http_client_init(&c);
  if (!h) return -1;
  esp_http_client_set_header(h, "Content-Type", "application/json");

  int codigo = -1;
  resp[0] = '\0';
  const int len = static_cast<int>(strlen(corpo));
  if (esp_http_client_open(h, len) == ESP_OK && esp_http_client_write(h, corpo, len) == len &&
      esp_http_client_fetch_headers(h) >= 0) {
    codigo = esp_http_client_get_status_code(h);
    int n = 0;
    int r;
    while (n < static_cast<int>(respMax) - 1 &&
           (r = esp_http_client_read(h, resp + n, static_cast<int>(respMax) - 1 - n)) > 0) {
      n += r;
    }
    resp[n] = '\0';
  }
  esp_http_client_close(h);
  esp_http_client_cleanup(h);
  return codigo;
}

Resultado enviarLote() {
  static Evento lote[LOTE_MAX];
  const size_t n = fila::ler(lote, LOTE_MAX);
  if (n == 0) return Resultado::Ok;

  cJSON* raiz = cJSON_CreateObject();
  cJSON_AddStringToObject(raiz, "p_chave", cfg.chave);
  cJSON_AddNumberToObject(raiz, "p_boot", bootAtual);
  cJSON_AddNumberToObject(raiz, "p_uptime_ms", static_cast<double>(uptimeMs()));
  cJSON* arr = cJSON_AddArrayToObject(raiz, "p_eventos");
  for (size_t i = 0; i < n; i++) {
    const Evento& e = lote[i];
    cJSON* o = cJSON_CreateObject();
    cJSON_AddNumberToObject(o, "boot", e.boot);
    cJSON_AddNumberToObject(o, "seq", e.seq);
    cJSON_AddStringToObject(o, "tipo", nomeTipo(e.tipo));
    cJSON_AddBoolToObject(o, "estavel", e.estavel != 0);
    cJSON_AddNumberToObject(o, "uptime_ms", static_cast<double>(e.uptimeMs));
    if (e.massaG != MASSA_AUSENTE) {
      cJSON_AddNumberToObject(o, "massa_g", e.massaG);
      cJSON_AddNumberToObject(o, "bruto", e.bruto);
      cJSON_AddNumberToObject(o, "desvio_g", e.desvioG);
    }
    if (e.epochMs > 0) cJSON_AddNumberToObject(o, "epoch_ms", static_cast<double>(e.epochMs));
    if (e.tipo == TipoEvento::Anula) {
      cJSON_AddNumberToObject(o, "ref_boot", e.refBoot);
      cJSON_AddNumberToObject(o, "ref_seq", e.refSeq);
    }
    cJSON_AddItemToArray(arr, o);
  }
  char* corpo = cJSON_PrintUnformatted(raiz);
  cJSON_Delete(raiz);
  if (!corpo) return Resultado::Falha;

  char resp[256];
  const int codigo = post("/rpc/ingerir", corpo, resp, sizeof resp);
  cJSON_free(corpo);

  if (codigo == 401 || codigo == 403) {
    recusada_ = true;
    ESP_LOGW(TAG, "chave recusada pelo servidor");
    return Resultado::Recusada;
  }
  if (codigo != 200) {
    ESP_LOGW(TAG, "envio falhou: %d %s", codigo, resp);
    return Resultado::Falha;
  }
  recusada_ = false;

  cJSON* ack = cJSON_Parse(resp);
  const cJSON* b = cJSON_GetObjectItem(ack, "boot");
  const cJSON* s = cJSON_GetObjectItem(ack, "seq");
  Resultado r = Resultado::Falha;
  if (cJSON_IsNumber(b) && cJSON_IsNumber(s)) {
    fila::confirmar(static_cast<uint32_t>(b->valuedouble), static_cast<uint32_t>(s->valuedouble));
    r = Resultado::Ok;
  } else {
    ESP_LOGW(TAG, "resposta inesperada: %s", resp);
  }
  cJSON_Delete(ack);
  return r;
}

void enviarStatus() {
  cJSON* raiz = cJSON_CreateObject();
  cJSON_AddStringToObject(raiz, "p_chave", cfg.chave);
  cJSON* s = cJSON_AddObjectToObject(raiz, "p_status");
  portENTER_CRITICAL(&trava);
  const int32_t massa = status.massaG;
  const bool est = status.estavel;
  const char* estado = status.estado;
  portEXIT_CRITICAL(&trava);
  cJSON_AddNumberToObject(s, "massa_g", massa);
  cJSON_AddBoolToObject(s, "estavel", est);
  cJSON_AddStringToObject(s, "estado", estado);
  cJSON_AddNumberToObject(s, "rssi", rssi());
  cJSON_AddNumberToObject(s, "fila", static_cast<double>(fila::pendentes()));
  cJSON_AddNumberToObject(s, "boot", bootAtual);
  cJSON_AddStringToObject(s, "versao", esp_app_get_description()->version);
  char* corpo = cJSON_PrintUnformatted(raiz);
  cJSON_Delete(raiz);
  if (!corpo) return;

  char resp[128];
  const int codigo = post("/rpc/status_posto", corpo, resp, sizeof resp);
  cJSON_free(corpo);
  if (codigo != 200) return;
  cJSON* r = cJSON_Parse(resp);
  const cJSON* bm = cJSON_GetObjectItem(r, "boot_max");
  const cJSON* sm = cJSON_GetObjectItem(r, "seq_max");
  if (cJSON_IsNumber(bm) && cJSON_IsNumber(sm)) {
    bootMax_ = static_cast<int64_t>(bm->valuedouble);
    seqMax_ = static_cast<int64_t>(sm->valuedouble);
  }
  cJSON_Delete(r);
}

void tarefa(void*) {
  bool ntpIniciado = false;
  TickType_t ultimaTentativaWifi = xTaskGetTickCount();
  TickType_t proximoEnvio = 0;
  TickType_t proximoStatus = 0;
  uint32_t espera = 1000;

  for (;;) {
    const TickType_t agora = xTaskGetTickCount();

    if (!conectado_) {
      if (agora - ultimaTentativaWifi > pdMS_TO_TICKS(5000)) {
        esp_wifi_connect();
        ultimaTentativaWifi = agora;
      }
      vTaskDelay(pdMS_TO_TICKS(200));
      continue;
    }

    if (!ntpIniciado) {
      if (cfg.ntp[0]) {
        strlcpy(hostNtp, cfg.ntp, sizeof hostNtp);
      } else {
        extrairHost(cfg.servidor, hostNtp, sizeof hostNtp);
      }
      esp_sntp_config_t sc = ESP_NETIF_SNTP_DEFAULT_CONFIG(hostNtp);
      esp_netif_sntp_init(&sc);
      ntpIniciado = true;
    }

    if (static_cast<int32_t>(agora - proximoEnvio) >= 0 && fila::pendentes() > 0) {
      switch (enviarLote()) {
        case Resultado::Ok:
          espera = 1000;
          proximoEnvio = agora + pdMS_TO_TICKS(fila::pendentes() > 0 ? 200 : INTERVALO_ENVIO_MS);
          break;
        case Resultado::Recusada:
          proximoEnvio = agora + pdMS_TO_TICKS(ESPERA_CHAVE_RECUSADA_MS);
          break;
        case Resultado::Falha:
          espera = espera * 2 > ESPERA_MAX_REDE_MS ? ESPERA_MAX_REDE_MS : espera * 2;
          proximoEnvio = agora + pdMS_TO_TICKS(espera);
          break;
      }
    }

    if (static_cast<int32_t>(agora - proximoStatus) >= 0) {
      enviarStatus();
      proximoStatus = agora + pdMS_TO_TICKS(INTERVALO_STATUS_MS);
    }

    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

}  // namespace

void iniciar(const Config& c, uint32_t boot) {
  cfg = c;
  bootAtual = boot;
  if (!cfg.ssid[0] || !cfg.servidor[0] || !cfg.chave[0]) {
    ESP_LOGW(TAG, "sem configuração: use os comandos ssid, senha, servidor e chave");
    return;
  }

  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  esp_netif_create_default_wifi_sta();
  wifi_init_config_t wc = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&wc));
  ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &aoEvento, nullptr, nullptr));
  ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &aoEvento, nullptr, nullptr));

  wifi_config_t w = {};
  strlcpy(reinterpret_cast<char*>(w.sta.ssid), cfg.ssid, sizeof w.sta.ssid);
  strlcpy(reinterpret_cast<char*>(w.sta.password), cfg.senha, sizeof w.sta.password);
  w.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;  // recusa redes abertas ou WEP
  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
  ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &w));
  ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
  ESP_ERROR_CHECK(esp_wifi_start());

  ativo_ = true;
  xTaskCreatePinnedToCore(tarefa, "rede", 8192, nullptr, 4, nullptr, 0);
}

bool ativo() { return ativo_; }

void informarMaxServidor(int64_t bootMax, int64_t seqMax) {
  bootMax_ = bootMax;
  seqMax_ = seqMax;
}

void publicarStatus(int32_t massaG, bool estavel, const char* estado) {
  portENTER_CRITICAL(&trava);
  status.massaG = massaG;
  status.estavel = estavel;
  status.estado = estado;
  portEXIT_CRITICAL(&trava);
}

bool conectado() { return conectado_; }
bool chaveRecusada() { return recusada_; }
int64_t bootMaxServidor() { return bootMax_; }
int64_t seqMaxServidor() { return seqMax_; }

int rssi() {
  wifi_ap_record_t ap;
  return conectado_ && esp_wifi_sta_get_ap_info(&ap) == ESP_OK ? ap.rssi : 0;
}

int64_t epochMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  if (tv.tv_sec < 1700000000) return -1;
  return int64_t(tv.tv_sec) * 1000 + tv.tv_usec / 1000;
}

uint64_t uptimeMs() { return static_cast<uint64_t>(esp_timer_get_time() / 1000); }

}  // namespace rede
