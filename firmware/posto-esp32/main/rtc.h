#pragma once
// Relógio DS3231 por I2C. Opcional: sem o módulo, as funções devolvem false e o posto segue sem hora.

#include <stdbool.h>
#include <time.h>

namespace rtc {

bool iniciar();                 // true se o módulo respondeu
bool presente();
bool ler(time_t& epoch);        // false se ausente ou se o oscilador parou (hora inválida)
bool gravar(time_t epoch);

}  // namespace rtc
