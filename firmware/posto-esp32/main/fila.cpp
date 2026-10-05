#include "fila.h"

#include "esp_log.h"
#include "esp_partition.h"
#include "fila_nucleo.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

namespace fila {
namespace {

const char* TAG = "fila";

class FlashParticao : public Flash {
 public:
  explicit FlashParticao(const esp_partition_t* p) : p_(p) {}
  size_t tamanho() const override { return p_->size; }
  bool ler(size_t off, void* dst, size_t n) override { return esp_partition_read(p_, off, dst, n) == ESP_OK; }
  bool escrever(size_t off, const void* src, size_t n) override {
    return esp_partition_write(p_, off, src, n) == ESP_OK;
  }
  bool apagar(size_t off, size_t n) override { return esp_partition_erase_range(p_, off, n) == ESP_OK; }

 private:
  const esp_partition_t* p_;
};

FlashParticao* flash = nullptr;
FilaNucleo* nucleo = nullptr;
SemaphoreHandle_t mtx = nullptr;

struct Trava {
  Trava() { xSemaphoreTake(mtx, portMAX_DELAY); }
  ~Trava() { xSemaphoreGive(mtx); }
};

}  // namespace

bool iniciar() {
  const esp_partition_t* p = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_ANY, "fila");
  if (!p) {
    ESP_LOGE(TAG, "partição 'fila' não encontrada");
    return false;
  }
  mtx = xSemaphoreCreateMutex();
  flash = new FlashParticao(p);
  nucleo = new FilaNucleo(*flash);
  Trava t;
  if (!nucleo->iniciar()) {
    ESP_LOGE(TAG, "falha ao ler a partição");
    return false;
  }
  ESP_LOGI(TAG, "%u pendentes, capacidade garantida %u", unsigned(nucleo->pendentes()),
           unsigned(nucleo->capacidade()));
  return true;
}

bool gravar(const Evento& e) {
  if (!nucleo) return false;
  Trava t;
  return nucleo->gravar(e);
}

size_t pendentes() {
  if (!nucleo) return 0;
  Trava t;
  return nucleo->pendentes();
}

size_t ler(Evento* destino, size_t max) {
  if (!nucleo) return 0;
  Trava t;
  return nucleo->ler(destino, max);
}

void confirmar(uint32_t boot, uint32_t seq) {
  if (!nucleo) return;
  Trava t;
  nucleo->confirmar(boot, seq);
}

bool ultimaChave(uint32_t& boot, uint32_t& seq) {
  if (!nucleo) return false;
  Trava t;
  return nucleo->ultimaChave(boot, seq);
}

}  // namespace fila
