#include "hx711.h"

#include "esp_rom_sys.h"

void Hx711::iniciar(gpio_num_t dout, gpio_num_t sck) {
  dout_ = dout;
  sck_ = sck;
  gpio_config_t in = {};
  in.pin_bit_mask = 1ULL << dout;
  in.mode = GPIO_MODE_INPUT;
  in.pull_up_en = GPIO_PULLUP_ENABLE;
  gpio_config(&in);
  gpio_config_t out = {};
  out.pin_bit_mask = 1ULL << sck;
  out.mode = GPIO_MODE_OUTPUT;
  gpio_config(&out);
  gpio_set_level(sck_, 0);  // SCK alto por mais de 60 µs desliga o HX711
}

int32_t Hx711::ler() {
  uint32_t v = 0;
  // SCK não pode ficar alto por mais de 60 µs: sem interrupção durante os 25 pulsos.
  portENTER_CRITICAL(&mux_);
  for (int i = 0; i < 24; i++) {
    gpio_set_level(sck_, 1);
    esp_rom_delay_us(1);
    v = (v << 1) | static_cast<uint32_t>(gpio_get_level(dout_));
    gpio_set_level(sck_, 0);
    esp_rom_delay_us(1);
  }
  // 25º pulso: próxima leitura no canal A com ganho 128.
  gpio_set_level(sck_, 1);
  esp_rom_delay_us(1);
  gpio_set_level(sck_, 0);
  esp_rom_delay_us(1);
  portEXIT_CRITICAL(&mux_);

  if (v & 0x800000u) v |= 0xFF000000u;  // complemento de dois em 24 bits
  return static_cast<int32_t>(v);
}
