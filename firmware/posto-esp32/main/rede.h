#pragma once
// Wi-Fi, hora e envio ao servidor. Roda numa tarefa própria no núcleo 0 (D3).

#include <stdint.h>

namespace rede {

struct Config {
  char ssid[33] = "";
  char senha[65] = "";
  char servidor[96] = "";  // ex.: http://192.168.0.10:3000
  char ntp[64] = "";       // vazio = host do servidor
  char chave[65] = "";
};

void iniciar(const Config& cfg, uint32_t boot);
void publicarStatus(int32_t massaG, bool estavel, const char* estado);

bool conectado();
bool chaveRecusada();
int rssi();
// Maiores boot e seq que o servidor já viu deste posto; -1 enquanto não souber.
int64_t bootMaxServidor();
int64_t seqMaxServidor();
int64_t epochMs();  // -1 sem hora sincronizada
uint64_t uptimeMs();

}  // namespace rede
