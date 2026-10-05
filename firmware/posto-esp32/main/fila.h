#pragma once
// Fila de eventos na partição "fila". Segura entre a tarefa de medição e a de rede (D3).
// A lógica está em fila_nucleo.h; aqui só a ligação com a flash do ESP32 e a trava.

#include <stddef.h>
#include <stdint.h>

#include "evento.h"

namespace fila {

bool iniciar();
bool gravar(const Evento& e);
size_t pendentes();
size_t ler(Evento* destino, size_t max);
void confirmar(uint32_t boot, uint32_t seq);
bool ultimaChave(uint32_t& boot, uint32_t& seq);

}  // namespace fila
