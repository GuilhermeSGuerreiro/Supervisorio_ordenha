#pragma once
// Janela de estabilidade. Código puro, sem Arduino, testado em test/test_nativo.cpp.

#include <stddef.h>
#include <stdint.h>

#include <algorithm>
#include <cmath>

template <size_t N>
class Janela {
 public:
  void limpar() {
    n_ = 0;
    pos_ = 0;
  }

  void adicionar(int32_t bruto) {
    buf_[pos_] = bruto;
    pos_ = (pos_ + 1) % N;
    if (n_ < N) n_++;
  }

  bool cheia() const { return n_ == N; }
  size_t tamanho() const { return n_; }

  // Mediana dos valores brutos da janela.
  int32_t medianaBruta() const {
    if (n_ == 0) return 0;
    int32_t tmp[N];
    std::copy(buf_, buf_ + n_, tmp);
    std::nth_element(tmp, tmp + n_ / 2, tmp + n_);
    return tmp[n_ / 2];
  }

  // Desvio padrão em unidades brutas.
  float desvioBruto() const {
    if (n_ < 2) return INFINITY;
    double soma = 0;
    for (size_t i = 0; i < n_; i++) soma += buf_[i];
    const double media = soma / n_;
    double acc = 0;
    for (size_t i = 0; i < n_; i++) acc += (buf_[i] - media) * (buf_[i] - media);
    return static_cast<float>(std::sqrt(acc / (n_ - 1)));
  }

 private:
  int32_t buf_[N] = {};
  size_t n_ = 0;
  size_t pos_ = 0;
};

// Conversão bruto -> gramas com calibração linear.
struct Calibracao {
  int32_t offset = 0;    // leitura bruta com plataforma vazia
  float fator = 0.0f;    // contagens por grama; 0 = não calibrado

  bool valida() const { return fator > 0.0f || fator < 0.0f; }

  int32_t gramas(int32_t bruto) const {
    if (!valida()) return 0;
    return static_cast<int32_t>(std::lround((bruto - offset) / fator));
  }

  float gramasDesvio(float desvioBruto) const {
    if (!valida()) return INFINITY;
    return std::fabs(desvioBruto / fator);
  }
};
