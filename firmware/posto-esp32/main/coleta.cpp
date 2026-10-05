#include "coleta.h"

#include <string.h>
#include <sys/time.h>

#include <atomic>

#include "cJSON.h"
#include "config.h"
#include "esp_app_desc.h"
#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "evento.h"
#include "fila.h"
#include "rede.h"
#include "rtc.h"

namespace coleta {
namespace {

const char* TAG = "coleta";

Config cfg;
uint32_t bootAtual = 0;
std::atomic<int> clientes_{0};

portMUX_TYPE trava = portMUX_INITIALIZER_UNLOCKED;
struct {
  int32_t massaG = 0;
  bool estavel = false;
  const char* estado = "?";
} status;

uint64_t uptimeMs() { return static_cast<uint64_t>(esp_timer_get_time() / 1000); }

int64_t epochMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  return tv.tv_sec < 1700000000 ? -1 : int64_t(tv.tv_sec) * 1000 + tv.tv_usec / 1000;
}

void aoEvento(void*, esp_event_base_t base, int32_t id, void*) {
  if (base != WIFI_EVENT) return;
  if (id == WIFI_EVENT_AP_STACONNECTED) clientes_++;
  if (id == WIFI_EVENT_AP_STADISCONNECTED && clientes_ > 0) clientes_--;
}

// Exige a chave do posto no cabeçalho. Sem chave cadastrada, aceita tudo (só na bancada).
bool autorizado(httpd_req_t* r) {
  if (!cfg.chave[0]) return true;
  char h[80] = "";
  httpd_req_get_hdr_value_str(r, "X-Chave", h, sizeof h);
  if (strcmp(h, cfg.chave) == 0) return true;
  httpd_resp_send_err(r, HTTPD_401_UNAUTHORIZED, "chave do posto incorreta");
  return false;
}

esp_err_t responderJson(httpd_req_t* r, cJSON* raiz) {
  char* txt = cJSON_PrintUnformatted(raiz);
  cJSON_Delete(raiz);
  if (!txt) return httpd_resp_send_500(r);
  httpd_resp_set_type(r, "application/json");
  const esp_err_t e = httpd_resp_send(r, txt, HTTPD_RESP_USE_STRLEN);
  cJSON_free(txt);
  return e;
}

// Lê o corpo JSON de um POST, até 1 KB.
cJSON* lerCorpo(httpd_req_t* r) {
  char buf[1024];
  if (r->content_len <= 0 || r->content_len >= static_cast<int>(sizeof buf)) return nullptr;
  int n = 0;
  while (n < r->content_len) {
    const int k = httpd_req_recv(r, buf + n, r->content_len - n);
    if (k <= 0) return nullptr;
    n += k;
  }
  buf[n] = 0;
  return cJSON_Parse(buf);
}

cJSON* infoJson() {
  cJSON* o = cJSON_CreateObject();
  cJSON_AddStringToObject(o, "versao", esp_app_get_description()->version);
  cJSON_AddNumberToObject(o, "posto", cfg.numeroPosto);
  cJSON_AddNumberToObject(o, "boot", bootAtual);
  cJSON_AddNumberToObject(o, "uptime_ms", static_cast<double>(uptimeMs()));
  cJSON_AddNumberToObject(o, "pendentes", static_cast<double>(fila::pendentes()));
  const int64_t e = epochMs();
  if (e > 0) cJSON_AddNumberToObject(o, "epoch_ms", static_cast<double>(e));
  cJSON_AddBoolToObject(o, "hora_ok", e > 0);
  cJSON_AddBoolToObject(o, "rtc", rtc::presente());
  portENTER_CRITICAL(&trava);
  cJSON_AddNumberToObject(o, "massa_g", status.massaG);
  cJSON_AddBoolToObject(o, "estavel", status.estavel);
  cJSON_AddStringToObject(o, "estado", status.estado);
  portEXIT_CRITICAL(&trava);
  return o;
}

esp_err_t getInfo(httpd_req_t* r) {
  if (!autorizado(r)) return ESP_OK;
  return responderJson(r, infoJson());
}

// GET /eventos?max=200 → os pendentes mais antigos, no mesmo formato que o servidor ingere.
esp_err_t getEventos(httpd_req_t* r) {
  if (!autorizado(r)) return ESP_OK;
  size_t max = LOTE_MAX_COLETA;
  char q[32], v[8];
  if (httpd_req_get_url_query_str(r, q, sizeof q) == ESP_OK && httpd_query_key_value(q, "max", v, sizeof v) == ESP_OK) {
    const int m = atoi(v);
    if (m > 0 && m < static_cast<int>(LOTE_MAX_COLETA)) max = m;
  }
  static Evento lote[LOTE_MAX_COLETA];
  const size_t n = fila::ler(lote, max);

  cJSON* raiz = cJSON_CreateObject();
  cJSON_AddNumberToObject(raiz, "boot", bootAtual);
  cJSON_AddNumberToObject(raiz, "uptime_ms", static_cast<double>(uptimeMs()));
  cJSON_AddNumberToObject(raiz, "pendentes", static_cast<double>(fila::pendentes()));
  cJSON* arr = cJSON_AddArrayToObject(raiz, "eventos");
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
  return responderJson(r, raiz);
}

// POST /confirmar {"boot":..,"seq":..,"boot_max":..,"seq_max":..}
esp_err_t postConfirmar(httpd_req_t* r) {
  if (!autorizado(r)) return ESP_OK;
  cJSON* c = lerCorpo(r);
  const cJSON* b = cJSON_GetObjectItem(c, "boot");
  const cJSON* s = cJSON_GetObjectItem(c, "seq");
  if (!cJSON_IsNumber(b) || !cJSON_IsNumber(s)) {
    cJSON_Delete(c);
    return httpd_resp_send_err(r, HTTPD_400_BAD_REQUEST, "boot e seq obrigatórios");
  }
  fila::confirmar(static_cast<uint32_t>(b->valuedouble), static_cast<uint32_t>(s->valuedouble));
  const cJSON* bm = cJSON_GetObjectItem(c, "boot_max");
  const cJSON* sm = cJSON_GetObjectItem(c, "seq_max");
  if (cJSON_IsNumber(bm) && cJSON_IsNumber(sm)) {
    rede::informarMaxServidor(static_cast<int64_t>(bm->valuedouble), static_cast<int64_t>(sm->valuedouble));
  }
  cJSON_Delete(c);
  ESP_LOGI(TAG, "confirmado até %.0f/%.0f, restam %u", b->valuedouble, s->valuedouble, unsigned(fila::pendentes()));
  return responderJson(r, infoJson());
}

// POST /hora {"epoch_ms":..} → acerta o relógio do sistema e o DS3231.
esp_err_t postHora(httpd_req_t* r) {
  if (!autorizado(r)) return ESP_OK;
  cJSON* c = lerCorpo(r);
  const cJSON* e = cJSON_GetObjectItem(c, "epoch_ms");
  if (!cJSON_IsNumber(e) || e->valuedouble < 1700000000000.0) {
    cJSON_Delete(c);
    return httpd_resp_send_err(r, HTTPD_400_BAD_REQUEST, "epoch_ms inválido");
  }
  const int64_t ms = static_cast<int64_t>(e->valuedouble);
  cJSON_Delete(c);
  struct timeval tv = {static_cast<time_t>(ms / 1000), static_cast<suseconds_t>((ms % 1000) * 1000)};
  settimeofday(&tv, nullptr);
  const bool gravou = rtc::gravar(tv.tv_sec);
  ESP_LOGI(TAG, "hora acertada%s", gravou ? " e gravada no DS3231" : "");
  return responderJson(r, infoJson());
}

}  // namespace

void iniciar(const Config& c, uint32_t boot) {
  cfg = c;
  bootAtual = boot;

  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  esp_netif_create_default_wifi_ap();
  wifi_init_config_t wc = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&wc));
  ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &aoEvento, nullptr, nullptr));

  wifi_config_t w = {};
  snprintf(reinterpret_cast<char*>(w.ap.ssid), sizeof w.ap.ssid, "%s%u", AP_PREFIXO, unsigned(cfg.numeroPosto));
  w.ap.ssid_len = strlen(reinterpret_cast<char*>(w.ap.ssid));
  const char* senha = cfg.senhaAp[0] ? cfg.senhaAp : AP_SENHA_PADRAO;
  strlcpy(reinterpret_cast<char*>(w.ap.password), senha, sizeof w.ap.password);
  w.ap.channel = AP_CANAL;
  w.ap.max_connection = 2;
  w.ap.authmode = WIFI_AUTH_WPA2_PSK;
  w.ap.pmf_cfg.required = false;
  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
  ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &w));
  ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
  ESP_ERROR_CHECK(esp_wifi_start());
  if (!cfg.senhaAp[0]) ESP_LOGW(TAG, "ponto de acesso com a senha padrão; troque com o comando ap_senha");
  ESP_LOGI(TAG, "ponto de acesso %s em 192.168.4.1", reinterpret_cast<char*>(w.ap.ssid));

  httpd_config_t hc = HTTPD_DEFAULT_CONFIG();
  hc.max_open_sockets = 3;
  hc.lru_purge_enable = true;
  httpd_handle_t srv = nullptr;
  ESP_ERROR_CHECK(httpd_start(&srv, &hc));
  const httpd_uri_t rotas[] = {
      {"/info", HTTP_GET, getInfo, nullptr},
      {"/eventos", HTTP_GET, getEventos, nullptr},
      {"/confirmar", HTTP_POST, postConfirmar, nullptr},
      {"/hora", HTTP_POST, postHora, nullptr},
  };
  for (const auto& rota : rotas) httpd_register_uri_handler(srv, &rota);
}

void publicarStatus(int32_t massaG, bool estavel, const char* estado) {
  portENTER_CRITICAL(&trava);
  status.massaG = massaG;
  status.estavel = estavel;
  status.estado = estado;
  portEXIT_CRITICAL(&trava);
}

int clientes() { return clientes_; }

}  // namespace coleta
