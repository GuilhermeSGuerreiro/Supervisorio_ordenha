#pragma once
#include <stdint.h>

enum class TipoEvento : uint8_t {
  Inicio = 0,
  Fim = 1,
  BaldeColocado = 2,
  BaldeRetirado = 3,
  Anula = 4,
};

inline const char* nomeTipo(TipoEvento t) {
  switch (t) {
    case TipoEvento::Inicio: return "inicio";
    case TipoEvento::Fim: return "fim";
    case TipoEvento::BaldeColocado: return "balde_colocado";
    case TipoEvento::BaldeRetirado: return "balde_retirado";
    case TipoEvento::Anula: return "anula";
  }
  return "?";
}

constexpr int32_t MASSA_AUSENTE = INT32_MIN;

// Registro gravado na fila em flash. Tamanho fixo: não mudar a ordem dos campos sem migrar a fila.
struct Evento {
  uint32_t boot;
  uint32_t seq;
  TipoEvento tipo;
  uint8_t estavel;
  uint16_t reservado;
  int32_t massaG;     // MASSA_AUSENTE quando não houver
  int32_t bruto;
  int32_t desvioG;
  uint32_t refBoot;   // só em Anula
  uint32_t refSeq;    // só em Anula
  uint64_t uptimeMs;
  int64_t epochMs;    // -1 sem hora sincronizada
};
static_assert(sizeof(Evento) == 48, "Evento deve ter 48 bytes");
