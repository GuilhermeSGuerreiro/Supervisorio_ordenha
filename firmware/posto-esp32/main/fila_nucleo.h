#pragma once
// Fila de eventos em flash, sem sistema de arquivos. Código puro, testado em test/test_nativo.cpp.
//
// A partição é um registro circular de slots de 64 bytes. Cada slot:
//   0  Evento (48)
//   48 magic (4)        'SCAR'
//   52 crc32 (4)        dos bytes 0..51
//   56 confirmado (4)   0xFFFFFFFF pendente; qualquer outro valor confirmado
//   60 reservado (4)
//
// Regras da flash NOR respeitadas: escrita só muda bits de 1 para 0, apagamento por setor de 4 KB.
// Queda de energia no meio de uma escrita deixa um slot inválido, que é pulado.
// Confirmar um evento só zera o campo confirmado, sem apagar nada.

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "evento.h"

class Flash {
 public:
  virtual ~Flash() = default;
  virtual size_t tamanho() const = 0;
  virtual bool ler(size_t off, void* dst, size_t n) = 0;
  virtual bool escrever(size_t off, const void* src, size_t n) = 0;
  virtual bool apagar(size_t off, size_t n) = 0;  // múltiplos de SETOR
};

inline uint32_t crc32(const uint8_t* p, size_t n) {
  uint32_t c = 0xFFFFFFFFu;
  for (size_t i = 0; i < n; i++) {
    c ^= p[i];
    for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u)));
  }
  return ~c;
}

class FilaNucleo {
 public:
  static constexpr size_t SETOR = 4096;
  static constexpr size_t SLOT = 64;
  static constexpr uint32_t MAGIC = 0x52414353u;  // "SCAR"
  static constexpr uint32_t LIVRE = 0xFFFFFFFFu;

  explicit FilaNucleo(Flash& f) : f_(f), slots_(f.tamanho() / SLOT) {}

  // Varre a partição e reconstrói a posição de escrita e o início dos pendentes.
  bool iniciar() {
    if (slots_ < 2 * (SETOR / SLOT)) return false;
    bool achou = false;
    size_t cabeca = 0;
    uint32_t cb = 0, cs = 0;
    for (size_t i = 0; i < slots_; i++) {
      Slot s;
      if (!lerSlot(i, s)) return false;
      if (!valido(s)) continue;
      if (!achou || maior(s.ev.boot, s.ev.seq, cb, cs)) {
        achou = true;
        cabeca = i;
        cb = s.ev.boot;
        cs = s.ev.seq;
      }
    }
    temChave_ = achou;
    ultBoot_ = cb;
    ultSeq_ = cs;
    if (!achou) {
      // Partição nova ou sem nada útil: apaga tudo uma vez.
      if (!f_.apagar(0, slots_ * SLOT)) return false;
      escrita_ = 0;
      inicio_ = 0;
      pendentes_ = 0;
      return true;
    }

    // Pendentes formam um trecho contíguo que termina na cabeça. Lixo de escrita interrompida é pulado.
    pendentes_ = 0;
    inicio_ = proximo(cabeca);
    size_t i = cabeca;
    for (size_t passo = 0; passo < slots_; passo++) {
      Slot s;
      if (!lerSlot(i, s)) return false;
      if (valido(s)) {
        if (s.confirmado != LIVRE) break;
        pendentes_++;
        inicio_ = i;
      } else if (apagado(s)) {
        break;
      }
      i = anterior(i);
    }

    // Escrita continua no primeiro slot apagado depois da cabeça.
    escrita_ = proximo(cabeca);
    for (size_t passo = 0; passo < slots_; passo++) {
      if (escrita_ % porSetor() == 0) break;  // início de setor: será apagado na próxima gravação
      Slot s;
      if (!lerSlot(escrita_, s)) return false;
      if (apagado(s)) break;
      escrita_ = proximo(escrita_);
    }
    return true;
  }

  size_t pendentes() const { return pendentes_; }

  // Maior (boot, seq) já gravado na partição. Usado para nunca reutilizar uma chave de evento
  // se a NVS for apagada e os contadores voltarem a zero.
  bool ultimaChave(uint32_t& boot, uint32_t& seq) const {
    boot = ultBoot_;
    seq = ultSeq_;
    return temChave_;
  }
  // Pendentes garantidos antes de a fila encher. Pode caber até slots_, conforme o alinhamento.
  size_t capacidade() const { return slots_ - porSetor() + 1; }

  bool gravar(const Evento& e) {
    if (escrita_ % porSetor() == 0) {
      // Entrando num setor: só pode apagar se nenhum pendente estiver nele.
      const size_t setor = escrita_ / porSetor();
      if (pendentes_ > 0 && pendenteNoSetor(setor)) return false;  // fila cheia
      if (!f_.apagar(setor * SETOR, SETOR)) return false;
    }
    Slot s;
    memset(&s, 0xFF, sizeof s);
    s.magic = MAGIC;
    s.ev = e;
    s.crc = crc32(reinterpret_cast<const uint8_t*>(&s), offsetof(Slot, crc));
    if (!f_.escrever(escrita_ * SLOT, &s, sizeof s)) return false;
    if (pendentes_ == 0) inicio_ = escrita_;
    pendentes_++;
    if (!temChave_ || maior(e.boot, e.seq, ultBoot_, ultSeq_)) {
      temChave_ = true;
      ultBoot_ = e.boot;
      ultSeq_ = e.seq;
    }
    escrita_ = proximo(escrita_);
    return true;
  }

  // Copia até `max` pendentes, do mais antigo para o mais novo.
  size_t ler(Evento* dst, size_t max) {
    size_t n = 0;
    size_t i = inicio_;
    for (size_t passo = 0; n < max && n < pendentes_ && passo < slots_; passo++) {
      Slot s;
      if (!lerSlot(i, s)) break;
      if (valido(s) && s.confirmado == LIVRE) dst[n++] = s.ev;
      i = proximo(i);
    }
    return n;
  }

  // Confirma todos os pendentes até (boot, seq), inclusive.
  void confirmar(uint32_t boot, uint32_t seq) {
    for (size_t passo = 0; pendentes_ > 0 && passo < slots_; passo++) {
      Slot s;
      if (!lerSlot(inicio_, s)) return;
      if (valido(s)) {
        if (s.confirmado != LIVRE) {  // já confirmado: só avança
        } else if (!maior(s.ev.boot, s.ev.seq, boot, seq)) {
          const uint32_t zero = 0;
          if (!f_.escrever(inicio_ * SLOT + offsetof(Slot, confirmado), &zero, sizeof zero)) return;
          pendentes_--;
        } else {
          return;
        }
      }
      inicio_ = proximo(inicio_);
    }
  }

 private:
  struct Slot {
    Evento ev;
    uint32_t magic;
    uint32_t crc;
    uint32_t confirmado;
    uint32_t reservado;
  };
  static_assert(sizeof(Slot) == SLOT, "slot deve ter 64 bytes");

  static bool maior(uint32_t b1, uint32_t s1, uint32_t b2, uint32_t s2) {
    return b1 > b2 || (b1 == b2 && s1 > s2);
  }

  static bool valido(const Slot& s) {
    return s.magic == MAGIC && s.crc == crc32(reinterpret_cast<const uint8_t*>(&s), offsetof(Slot, crc));
  }

  static bool apagado(const Slot& s) {
    const uint8_t* p = reinterpret_cast<const uint8_t*>(&s);
    for (size_t i = 0; i < sizeof s; i++)
      if (p[i] != 0xFF) return false;
    return true;
  }

  static constexpr size_t porSetor() { return SETOR / SLOT; }
  size_t proximo(size_t i) const { return (i + 1) % slots_; }
  size_t anterior(size_t i) const { return (i + slots_ - 1) % slots_; }

  bool pendenteNoSetor(size_t setor) const {
    // O trecho pendente vai de inicio_ até escrita_ - 1, em ordem circular.
    for (size_t k = 0, i = inicio_; k < slots_ && i != escrita_; k++, i = proximo(i))
      if (i / porSetor() == setor) return true;
    return false;
  }

  bool lerSlot(size_t i, Slot& s) { return f_.ler(i * SLOT, &s, sizeof s); }

  Flash& f_;
  size_t slots_;
  size_t escrita_ = 0;
  size_t inicio_ = 0;
  size_t pendentes_ = 0;
  bool temChave_ = false;
  uint32_t ultBoot_ = 0;
  uint32_t ultSeq_ = 0;
};
