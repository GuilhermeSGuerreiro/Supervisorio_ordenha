# Decisões de arquitetura

Cada decisão tem contexto, escolha e consequência. Ao mudar uma decisão, acrescentar uma nova em vez de apagar a antiga.

## D1 · O posto mede, o servidor decide

**Contexto.** A associação entre leitura e vaca muda: operador esquece, escolhe errado, corrige depois.

**Decisão.** O posto só registra eventos com peso: início, fim, balde colocado, balde retirado e anulação.
Vaca, sessão, parcial, produção e validade são calculados no servidor.

**Consequência.** O firmware fica pequeno e raramente precisa de atualização. Correções de associação não exigem mexer no posto.

## D2 · Identificador do evento sem depender do relógio

**Contexto.** O ESP32 não tem relógio de tempo real. Depois de um reinício sem rede, a hora é desconhecida.

**Decisão.** Cada evento é identificado por `posto + boot + seq`.
- `boot` é um contador gravado na memória não volátil, incrementado a cada partida.
- `seq` é um contador gravado na memória não volátil, incrementado a cada evento e nunca reiniciado.
- O servidor tem restrição de unicidade nessa chave e ignora repetições.

- Se a NVS for apagada, o posto recupera os contadores pela maior chave guardada na fila.
- Se a flash inteira for apagada, o servidor informa o maior seq que já recebeu e o posto ajusta os contadores antes de gerar eventos.

**Consequência.** O posto pode reenviar à vontade sem duplicar. Reinício não gera colisão.

## D3 · Guardar e reenviar no posto

**Decisão.** Todo evento é gravado primeiro numa partição própria da flash e só depois enviado.
A partição é um registro circular de slots de 64 bytes com CRC, sem sistema de arquivos.
Queda de energia no meio de uma gravação deixa só um slot inválido, que é pulado.
O servidor responde com o último evento confirmado, e o posto marca como confirmado tudo até ele.
Eventos são enviados em ordem, do mais antigo para o mais novo.
Rede e medição rodam em tarefas separadas, em núcleos diferentes do ESP32. Um envio lento não faz o posto perder um toque no botão.

**Consequência.** Queda de Wi-Fi ou do servidor não perde dados. A partição de 256 KB guarda pelo menos 4.033 eventos pendentes, o que dá semanas sem rede.
A lógica da fila é código puro, testado no PC com uma flash simulada em `firmware/posto-esp32/test/test_nativo.cpp`.

## D4 · O servidor nunca recusa um evento por regra de negócio

**Contexto.** Se o servidor recusar um evento estranho, como um fim sem início, o posto fica preso tentando reenviar.

**Decisão.** O servidor só recusa por chave inválida ou dado malformado.
Evento que não se encaixa na sequência é gravado, confirmado e marcado com erro para conferência no painel.

## D5 · PostgreSQL com PostgREST no servidor local

**Contexto.** Supabase completo é pesado para um Raspberry. O desenvolvedor já conhece Supabase, que usa PostgREST por baixo.

**Decisão.**
- PostgreSQL 16 com o esquema em `server/db/schema.sql`.
- PostgREST expondo só funções e visões explicitamente liberadas.
- Toda a regra de ingestão em funções SQL, testadas por `server/db/teste.sql`.
- n8n fica para tarefas fora do caminho crítico, como relatórios e sincronização com a nuvem.

**Consequência.** Uma peça a menos entre o posto e o banco. O mesmo esquema sobe para o Supabase na nuvem quando houver sincronização.

## D6 · Multi-fazenda desde o início

**Decisão.** As tabelas principais carregam `fazenda_id`, mesmo com uma fazenda só.

**Consequência.** Custo quase zero agora. Evita migração quando o produto tiver vários clientes sincronizando para a mesma nuvem.

## D7 · Massa em gramas inteiros

**Decisão.** Toda massa trafega e é guardada em gramas, como inteiro. Litros só aparecem em relatório, pela densidade parametrizada.

**Consequência.** Sem erro de arredondamento em ponto flutuante nas somas.

## D8 · Nada é apagado

**Decisão.** Eventos são imutáveis. Correção é feita por anulação, com quem anulou e quando.

**Consequência.** Auditoria completa. Relatórios filtram registros anulados.

## D9 · Credenciais fora do repositório e fora do binário

**Decisão.** Rede Wi-Fi, senha, endereço do servidor e chave do posto são gravados no ESP32 por comando na porta serial, na instalação.
O servidor guarda só o hash SHA-256 da chave do posto.

**Consequência.** O mesmo binário serve para todos os postos. Uma chave vazada é revogada no banco sem regravar o firmware.

## D10 · HTTP sem TLS na rede local, por enquanto

**Contexto.** TLS no ESP32 com certificado próprio exige gestão de certificados, que não cabe no piloto.

**Decisão.** HTTP simples, só na rede local com WPA2 ou WPA3, servidor sem porta exposta à internet, e preferencialmente numa rede separada para os postos.

**Consequência.** Quem estiver na rede Wi-Fi pode ver a chave do posto em trânsito. Antes do piloto externo, reavaliar TLS com certificado fixado no firmware.

## D11 · Firmware em ESP-IDF

**Contexto.** O protótipo começou em Arduino. O produto precisa de controle fino sobre tarefas, núcleos, flash e Wi-Fi, e de um caminho de manutenção de longo prazo.

**Decisão.**
- ESP-IDF 5.3, versão com suporte de longo prazo.
- Sem componentes externos: driver do HX711 próprio, fila direto na partição, JSON com o cJSON do próprio IDF.
- Regras puras em cabeçalhos sem dependência do IDF, testadas no PC com o compilador do sistema.

**Consequência.** Build reproduzível sem gerenciador de componentes. Watchdog e detecção de queda de tensão ligados por padrão.
