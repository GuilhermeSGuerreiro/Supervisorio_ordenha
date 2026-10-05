#pragma once
// Parâmetros fixos do posto. Credenciais NÃO ficam aqui: são gravadas pela serial (docs/06-decisoes.md, D9).

#include <stdint.h>

// Pinos (docs/03-componentes.md). Não usar 0, 2, 5, 12 e 15.
constexpr int PINO_HX_DOUT = 16;
constexpr int PINO_HX_SCK = 17;
constexpr int PINO_BOTAO = 25;
constexpr int PINO_LED_VERDE = 26;
constexpr int PINO_LED_VERMELHO = 27;

// Estabilidade (docs/02-operacao.md). HX711 a 10 amostras/s.
constexpr uint32_t JANELA_AMOSTRAS = 40;        // 4 s
constexpr float DESVIO_MAX_G = 30.0f;            // desvio padrão máximo para considerar estável
constexpr uint32_t ESPERA_MAX_ESTAVEL_MS = 30000;
constexpr uint32_t SEM_AMOSTRA_FALHA_MS = 1500;  // HX711 sem responder

// Botão
constexpr uint32_t DEBOUNCE_MS = 30;
constexpr uint32_t TOQUE_CURTO_MAX_MS = 1500;
constexpr uint32_t TOQUE_LONGO_MS = 2000;
constexpr uint32_t TOQUE_ANULA_MS = 6000;

// Segurança da célula: acima disso o LED acusa sobrecarga.
constexpr int32_t CARGA_MAXIMA_G = 110000;

// Rede
constexpr uint32_t INTERVALO_ENVIO_MS = 2000;
constexpr uint32_t INTERVALO_STATUS_MS = 5000;
constexpr uint32_t ESPERA_MAX_REDE_MS = 30000;
constexpr uint32_t ESPERA_CHAVE_RECUSADA_MS = 60000;
constexpr uint16_t TIMEOUT_HTTP_MS = 4000;
constexpr size_t LOTE_MAX = 20;
