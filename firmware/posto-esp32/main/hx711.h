#pragma once
// Driver mínimo do HX711: canal A, ganho 128, 10 amostras/s (pino RATE do módulo em GND).

#include <stdint.h>

#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"

class Hx711 {
 public:
  void iniciar(gpio_num_t dout, gpio_num_t sck);
  bool pronto() const { return gpio_get_level(dout_) == 0; }
  // Só chamar com pronto() verdadeiro. Leva cerca de 50 µs com interrupções desligadas neste núcleo.
  int32_t ler();

 private:
  gpio_num_t dout_ = GPIO_NUM_NC;
  gpio_num_t sck_ = GPIO_NUM_NC;
  portMUX_TYPE mux_ = portMUX_INITIALIZER_UNLOCKED;
};
