#include "rtc.h"

#include <string.h>

#include "config.h"
#include "driver/i2c_master.h"
#include "esp_log.h"

namespace rtc {
namespace {

const char* TAG = "rtc";
constexpr uint8_t ENDERECO = 0x68;
constexpr uint8_t REG_SEGUNDOS = 0x00;
constexpr uint8_t REG_STATUS = 0x0F;
constexpr uint8_t BIT_OSF = 0x80;  // oscilador parou: hora não confiável

i2c_master_bus_handle_t bus = nullptr;
i2c_master_dev_handle_t dev = nullptr;

uint8_t deBcd(uint8_t v) { return (v >> 4) * 10 + (v & 0x0F); }
uint8_t paraBcd(uint8_t v) { return ((v / 10) << 4) | (v % 10); }

bool lerRegs(uint8_t reg, uint8_t* dst, size_t n) {
  return dev && i2c_master_transmit_receive(dev, &reg, 1, dst, n, 100) == ESP_OK;
}

bool escreverRegs(uint8_t reg, const uint8_t* src, size_t n) {
  uint8_t buf[16];
  if (!dev || n > sizeof buf - 1) return false;
  buf[0] = reg;
  memcpy(buf + 1, src, n);
  return i2c_master_transmit(dev, buf, n + 1, 100) == ESP_OK;
}

}  // namespace

bool iniciar() {
  i2c_master_bus_config_t bc = {};
  bc.i2c_port = I2C_NUM_0;
  bc.sda_io_num = static_cast<gpio_num_t>(PINO_I2C_SDA);
  bc.scl_io_num = static_cast<gpio_num_t>(PINO_I2C_SCL);
  bc.clk_source = I2C_CLK_SRC_DEFAULT;
  bc.glitch_ignore_cnt = 7;
  bc.flags.enable_internal_pullup = true;
  if (i2c_new_master_bus(&bc, &bus) != ESP_OK) return false;
  if (i2c_master_probe(bus, ENDERECO, 50) != ESP_OK) {
    ESP_LOGW(TAG, "DS3231 não encontrado; posto sem relógio");
    return false;
  }
  i2c_device_config_t dc = {};
  dc.dev_addr_length = I2C_ADDR_BIT_LEN_7;
  dc.device_address = ENDERECO;
  dc.scl_speed_hz = 100000;
  if (i2c_master_bus_add_device(bus, &dc, &dev) != ESP_OK) return false;
  ESP_LOGI(TAG, "DS3231 presente");
  return true;
}

bool presente() { return dev != nullptr; }

bool ler(time_t& epoch) {
  uint8_t st;
  if (!lerRegs(REG_STATUS, &st, 1) || (st & BIT_OSF)) return false;
  uint8_t r[7];
  if (!lerRegs(REG_SEGUNDOS, r, 7)) return false;
  struct tm t = {};
  t.tm_sec = deBcd(r[0] & 0x7F);
  t.tm_min = deBcd(r[1] & 0x7F);
  t.tm_hour = deBcd(r[2] & 0x3F);  // modo 24 h
  t.tm_mday = deBcd(r[4] & 0x3F);
  t.tm_mon = deBcd(r[5] & 0x1F) - 1;
  t.tm_year = deBcd(r[6]) + 100;  // 20xx
  // O relógio guarda UTC. timegm não existe no newlib: converte sem fuso.
  setenv("TZ", "UTC0", 1);
  tzset();
  epoch = mktime(&t);
  return epoch > 1700000000;
}

bool gravar(time_t epoch) {
  struct tm t;
  gmtime_r(&epoch, &t);
  uint8_t r[7] = {paraBcd(t.tm_sec), paraBcd(t.tm_min), paraBcd(t.tm_hour), paraBcd(t.tm_wday + 1),
                  paraBcd(t.tm_mday), paraBcd(t.tm_mon + 1), paraBcd(t.tm_year - 100)};
  if (!escreverRegs(REG_SEGUNDOS, r, 7)) return false;
  uint8_t st;
  if (lerRegs(REG_STATUS, &st, 1)) {
    st &= ~BIT_OSF;  // hora válida de novo
    escreverRegs(REG_STATUS, &st, 1);
  }
  return true;
}

}  // namespace rtc
