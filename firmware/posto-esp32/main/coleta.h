#pragma once
// Coleta por aproximação (D14): o posto cria um ponto de acesso Wi-Fi e serve a fila por HTTP.
// O computador conecta, baixa os eventos, grava no banco e confirma. Sem servidor na fazenda.

#include <stdint.h>

namespace coleta {

struct Config {
  uint8_t numeroPosto = 1;
  char senhaAp[65] = "";
  char chave[65] = "";  // mesma chave do posto no banco; exigida no cabeçalho X-Chave
};

void iniciar(const Config& cfg, uint32_t boot);
void publicarStatus(int32_t massaG, bool estavel, const char* estado);
int clientes();

}  // namespace coleta
