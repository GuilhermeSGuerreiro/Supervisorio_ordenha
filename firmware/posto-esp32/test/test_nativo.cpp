// Teste nativo das regras puras do posto: máquina de estados, janela e calibração.
// Roda no PC, sem ESP32:
//   g++ -std=c++17 -Wall -Wextra -Imain test/test_nativo.cpp -o /tmp/teste_posto && /tmp/teste_posto

#include <cstdio>
#include <cstdlib>

#include <cstring>
#include <vector>

#include "estado.h"
#include "fila_nucleo.h"
#include "janela.h"

static int falhas = 0;
#define CHECA(cond)                                              \
  do {                                                           \
    if (!(cond)) {                                               \
      std::printf("FALHA %s:%d  %s\n", __FILE__, __LINE__, #cond); \
      falhas++;                                                  \
    }                                                            \
  } while (0)

static void testaTransicoes() {
  using E = EstadoPosto;
  using T = TipoEvento;

  auto t = transicao(E::SemBalde, Acao::Balde);
  CHECA(t.aceita && t.tipo == T::BaldeColocado && t.proximo == E::Ocioso);
  CHECA(!transicao(E::SemBalde, Acao::Marca).aceita);

  t = transicao(E::Ocioso, Acao::Marca);
  CHECA(t.aceita && t.tipo == T::Inicio && t.proximo == E::Ordenhando);
  t = transicao(E::Ocioso, Acao::Balde);
  CHECA(t.aceita && t.tipo == T::BaldeRetirado && t.proximo == E::SemBalde);

  t = transicao(E::Ocioso, Acao::Pula);
  CHECA(t.aceita && t.tipo == T::Pulo && t.proximo == E::Ocioso);  // pular vaca não muda o estado
  CHECA(!transicao(E::SemBalde, Acao::Pula).aceita);
  CHECA(!transicao(E::Ordenhando, Acao::Pula).aceita);

  t = transicao(E::Ordenhando, Acao::Marca);
  CHECA(t.aceita && t.tipo == T::Fim && t.proximo == E::Ocioso);
  t = transicao(E::Ordenhando, Acao::Balde);
  CHECA(!t.aceita && t.proximo == E::Ordenhando);  // balde com ordenha aberta é recusado
}

static void testaJanela() {
  Janela<40> j;
  CHECA(!j.cheia());
  for (int i = 0; i < 39; i++) j.adicionar(1000);
  CHECA(!j.cheia());
  j.adicionar(1000);
  CHECA(j.cheia() && j.tamanho() == 40);
  CHECA(j.medianaBruta() == 1000);
  CHECA(j.desvioBruto() == 0.0f);

  // Vibração periódica de ±200 contagens em torno de 50000: mediana robusta.
  for (int i = 0; i < 40; i++) j.adicionar(50000 + (i % 2 ? 200 : -200));
  CHECA(j.medianaBruta() >= 49800 && j.medianaBruta() <= 50200);
  CHECA(j.desvioBruto() > 190.0f && j.desvioBruto() < 210.0f);

  // Um pico isolado não move a mediana.
  for (int i = 0; i < 39; i++) j.adicionar(70000);
  j.adicionar(9000000);
  CHECA(j.medianaBruta() == 70000);
}

static void testaCalibracao() {
  Calibracao c;
  CHECA(!c.valida());
  CHECA(c.gramas(123456) == 0);

  // 20 contagens por grama, offset 8000: 10 kg = 8000 + 200000.
  c.offset = 8000;
  c.fator = 20.0f;
  CHECA(c.valida());
  CHECA(c.gramas(208000) == 10000);
  CHECA(c.gramas(8000) == 0);
  CHECA(c.gramasDesvio(600.0f) == 30.0f);

  // Célula montada invertida: fator negativo também vale.
  c.fator = -20.0f;
  CHECA(c.valida());
  CHECA(c.gramas(8000 - 200000) == 10000);
  CHECA(c.gramasDesvio(600.0f) == 30.0f);
}

// Flash NOR simulada: escrita só zera bits, apagamento por setor, contagem de desgaste.
class FlashRam : public Flash {
 public:
  explicit FlashRam(size_t n) : mem(n, 0x00) {}  // começa suja, como uma partição nunca usada
  size_t tamanho() const override { return mem.size(); }
  bool ler(size_t off, void* dst, size_t n) override {
    if (off + n > mem.size()) return false;
    std::memcpy(dst, &mem[off], n);
    return true;
  }
  bool escrever(size_t off, const void* src, size_t n) override {
    if (off + n > mem.size()) return false;
    const auto* p = static_cast<const uint8_t*>(src);
    size_t limite = n;
    if (corteEmBytes >= 0) {  // queda de energia no meio desta escrita
      limite = std::min<size_t>(n, static_cast<size_t>(corteEmBytes));
      corteEmBytes = -1;
      for (size_t i = 0; i < limite; i++) mem[off + i] &= p[i];
      return false;
    }
    for (size_t i = 0; i < limite; i++) mem[off + i] &= p[i];  // NOR: 1 -> 0 apenas
    return true;
  }
  bool apagar(size_t off, size_t n) override {
    if (off % FilaNucleo::SETOR || n % FilaNucleo::SETOR || off + n > mem.size()) return false;
    std::memset(&mem[off], 0xFF, n);
    apagamentos += n / FilaNucleo::SETOR;
    return true;
  }
  std::vector<uint8_t> mem;
  long corteEmBytes = -1;
  int apagamentos = 0;
};

static Evento ev(uint32_t boot, uint32_t seq) {
  Evento e{};
  e.boot = boot;
  e.seq = seq;
  e.tipo = TipoEvento::Inicio;
  e.massaG = static_cast<int32_t>(seq * 10);
  e.epochMs = -1;
  return e;
}

static void testaFila() {
  constexpr size_t TAM = 4 * FilaNucleo::SETOR;  // 4 setores = 256 slots
  FlashRam flash(TAM);

  {  // partição suja é apagada no primeiro uso
    FilaNucleo f(flash);
    CHECA(f.iniciar());
    CHECA(f.pendentes() == 0);
    CHECA(f.capacidade() == 193);
    uint32_t b, s;
    CHECA(!f.ultimaChave(b, s));
  }

  {  // grava, lê em ordem, confirma parcialmente
    FilaNucleo f(flash);
    CHECA(f.iniciar());
    for (uint32_t i = 1; i <= 10; i++) CHECA(f.gravar(ev(1, i)));
    CHECA(f.pendentes() == 10);
    Evento buf[20];
    CHECA(f.ler(buf, 4) == 4);
    CHECA(buf[0].seq == 1 && buf[3].seq == 4);
    f.confirmar(1, 4);
    CHECA(f.pendentes() == 6);
    CHECA(f.ler(buf, 20) == 6 && buf[0].seq == 5 && buf[5].seq == 10);
    f.confirmar(1, 4);  // confirmação repetida não muda nada
    CHECA(f.pendentes() == 6);
  }

  {  // reinício: reconstrói pendentes e última chave a partir da flash
    FilaNucleo f(flash);
    CHECA(f.iniciar());
    CHECA(f.pendentes() == 6);
    uint32_t b, s;
    CHECA(f.ultimaChave(b, s) && b == 1 && s == 10);
    Evento buf[20];
    CHECA(f.ler(buf, 20) == 6 && buf[0].seq == 5);
    CHECA(f.gravar(ev(2, 11)));
    CHECA(f.ler(buf, 20) == 7 && buf[6].boot == 2 && buf[6].seq == 11);
    f.confirmar(2, 11);
    CHECA(f.pendentes() == 0);
  }

  {  // queda de energia no meio de uma gravação: slot inválido é pulado
    FilaNucleo f(flash);
    CHECA(f.iniciar());
    CHECA(f.gravar(ev(3, 12)));
    flash.corteEmBytes = 30;
    CHECA(!f.gravar(ev(3, 13)));  // posto desligou aqui
    FilaNucleo g(flash);           // religou
    CHECA(g.iniciar());
    CHECA(g.pendentes() == 1);
    CHECA(g.gravar(ev(4, 14)));
    Evento buf[4];
    CHECA(g.ler(buf, 4) == 2 && buf[0].seq == 12 && buf[1].seq == 14);
    FilaNucleo h(flash);  // e reiniciou de novo, com o lixo entre dois pendentes
    CHECA(h.iniciar());
    CHECA(h.pendentes() == 2);
    h.confirmar(4, 14);
    CHECA(h.pendentes() == 0);
  }

  {  // volta completa no anel e fila cheia sem rede
    FilaNucleo f(flash);
    CHECA(f.iniciar());
    uint32_t seq = 100;
    for (int volta = 0; volta < 5; volta++) {  // várias voltas com confirmação
      for (int i = 0; i < 150; i++) CHECA(f.gravar(ev(5, ++seq)));
      f.confirmar(5, seq);
      CHECA(f.pendentes() == 0);
    }
    size_t gravados = 0;
    while (f.gravar(ev(6, ++seq))) gravados++;
    CHECA(gravados >= f.capacidade());
    CHECA(gravados <= TAM / FilaNucleo::SLOT);
    const size_t cheios = f.pendentes();
    FilaNucleo g(flash);  // reinício com a fila cheia preserva tudo
    CHECA(g.iniciar());
    CHECA(g.pendentes() == cheios);
    Evento buf[300];
    const size_t n = g.ler(buf, 300);
    CHECA(n == cheios);
    bool ordem = true;
    for (size_t i = 1; i < n; i++) ordem = ordem && buf[i].seq == buf[i - 1].seq + 1;
    CHECA(ordem);
    g.confirmar(buf[n - 1].boot, buf[n - 1].seq);
    CHECA(g.pendentes() == 0);
    CHECA(g.gravar(ev(7, 1)));  // volta a aceitar
  }

  {  // queda de energia ao confirmar: confirmação parcial conta como confirmada
    FilaNucleo f(flash);
    CHECA(f.iniciar());
    f.confirmar(7, 1);
    CHECA(f.pendentes() == 0);
    CHECA(f.gravar(ev(8, 1)));
    CHECA(f.gravar(ev(8, 2)));
    flash.corteEmBytes = 1;
    f.confirmar(8, 1);
    FilaNucleo g(flash);
    CHECA(g.iniciar());
    CHECA(g.pendentes() == 1);
    Evento buf[2];
    CHECA(g.ler(buf, 2) == 1 && buf[0].seq == 2);
  }
}

int main() {
  testaFila();
  testaTransicoes();
  testaJanela();
  testaCalibracao();
  if (falhas) {
    std::printf("%d falha(s)\n", falhas);
    return EXIT_FAILURE;
  }
  std::printf("test_nativo: todos os testes passaram\n");
  return EXIT_SUCCESS;
}
