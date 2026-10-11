# Vídeo de demonstração

Vídeo de cerca de 100 segundos, Full HD, sem narração, com texto em português.
Mostra o problema observado em campo, o posto, a ordem fixa, a coleta por aproximação, o que o sistema calcula, a medição de uma mudança de manejo e a exportação.

## De onde vêm os números

| Cena | Origem |
|---|---|
| Ordenha de 60 minutos, máquina 20 | Observação de campo, outubro de 2026: 9 vacas, 3 postos, 4 rodadas, cerca de 5 min por vaca |
| Produção por vaca, rebanho, tempo de máquina e de troca | `simulacao.sql` passada pelo banco real; números calculados pelas visões do sistema |
| Mudança de manejo | Mesma simulação: ração nova no lote A no dia 11, onda de calor nos dias 14 a 18. Efeito real simulado de 0,8 kg; o sistema estimou o valor com intervalo de confiança |
| Exportação ICAR | Exportação da simulação validada contra os esquemas oficiais do ICAR |
| Investimento da etapa 1 | `planilhas/bom.csv` |

O vídeo diz na tela quais resultados são simulados.

## Como gerar

1. Simular e extrair os números. Precisa de PostgreSQL com permissão para criar banco:

   ```
   python3 demo/video/gerar_dados.py
   ```

   Gera `dados.json`. Com o repositório do padrão ICAR em `ICAR_ADE_DIR`, também valida a exportação.

2. Gravar. Precisa de Node com Playwright, Chromium e ffmpeg:

   ```
   node demo/video/gravar.cjs
   ```

   Sai em `demo/video/saida/scara-demo.mp4`. Para conferir quadros soltos: `node demo/video/gravar.cjs --quadros 10,40,70`.

Para editar textos, tempos ou a ordem das cenas, mexa em `video.html`. Cada cena tem duração e animação próprias, e o gravador chama `render(t)` quadro a quadro, então o resultado é sempre igual.
