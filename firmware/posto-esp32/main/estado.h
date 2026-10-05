#pragma once
#include <stdint.h>

// Máquina de estados do posto (docs/02-operacao.md).
enum class EstadoPosto : uint8_t {
  SemBalde = 0,
  Ocioso = 1,
  Ordenhando = 2,
};

inline const char* nomeEstado(EstadoPosto e) {
  switch (e) {
    case EstadoPosto::SemBalde: return "SEM_BALDE";
    case EstadoPosto::Ocioso: return "OCIOSO";
    case EstadoPosto::Ordenhando: return "ORDENHANDO";
  }
  return "?";
}

#include "evento.h"

enum class Acao : uint8_t {
  Marca = 0,  // toque curto
  Balde = 1,  // toque longo
};

struct Transicao {
  bool aceita;
  TipoEvento tipo;
  EstadoPosto proximo;
};

// Regras puras, testadas em test/test_nativo.cpp.
inline Transicao transicao(EstadoPosto e, Acao a) {
  switch (e) {
    case EstadoPosto::SemBalde:
      if (a == Acao::Balde) return {true, TipoEvento::BaldeColocado, EstadoPosto::Ocioso};
      break;
    case EstadoPosto::Ocioso:
      if (a == Acao::Marca) return {true, TipoEvento::Inicio, EstadoPosto::Ordenhando};
      return {true, TipoEvento::BaldeRetirado, EstadoPosto::SemBalde};
    case EstadoPosto::Ordenhando:
      if (a == Acao::Marca) return {true, TipoEvento::Fim, EstadoPosto::Ocioso};
      break;  // balde com ordenha aberta é recusado
  }
  return {false, TipoEvento::Anula, e};
}
