# Escopo do piloto

## Contexto

- Ordenha balde ao pé, 3 vacas por vez, 3 baldes separados acionados por vácuo.
- Cada balde acumula o leite de várias vacas e é esvaziado antes de atingir o limite operacional.
- As vacas comem concentrado durante a ordenha.
- Piloto na fazenda de um familiar, em Morada Nova-CE, financiado por etapa.
- Objetivo posterior: produto para produtores de Morada Nova e região. O município é o maior produtor de leite do Ceará, com 117,3 milhões de litros em 2025 segundo a Pesquisa da Pecuária Municipal do IBGE.

## Ideia central

O supervisório é o instrumento que mede o efeito de cada mudança de manejo.
Troca de ração, realocação de vacas, sombra, horário de ordenha: cada mudança é registrada com data e alvo, e o sistema mostra se a produção melhorou, piorou ou não mudou, descontando estágio de lactação e calor.
O método está em `docs/08-mensuracao-manejo.md`.

A prova de conceito começa só com o supervisório. Nenhuma mudança é proposta antes de existir linha de base.

## Prova de conceito interna

- Fazenda da família com cerca de 12 vacas em lactação.
- As vacas entram sempre na mesma ordem e sempre no mesmo posto. O sistema usa essa ordem para saber qual vaca está no posto, sem celular e sem identificação eletrônica.
- Um posto com ESP32 que guarda tudo na própria memória. Sem servidor na fazenda, sem internet, sem tempo real.
- Coleta por aproximação: o computador chega, conecta no Wi-Fi do posto e baixa os eventos. O banco de dados roda no notebook.
- Servidor local, três postos e painel em tempo real ficam para a segunda etapa, se a primeira provar a medição.

## Perguntas que o MVP responde

| Pergunta | Dado que responde |
|---|---|
| Quanto cada vaca produziu? | Soma das parciais da ordenha, por turno e por dia |
| Quanto concentrado foi fornecido? | Medidas lançadas convertidas para kg, marcadas como conferidas ou estimadas |
| Qual animal mudou e merece atenção? | Queda em relação à média da própria vaca no mesmo turno, ocorrências |
| Como produção e gasto evoluem? | Série diária de leite e concentrado por vaca e do rebanho, kg de leite por kg de concentrado |
| A mudança de manejo funcionou? | Efeito em kg por vaca por dia com intervalo de confiança, comparado com lote de controle quando houver, com ITU das duas janelas |

## Dentro do MVP

- Balança por posto com ESP32 e envio por Wi-Fi local.
- Botão físico e LED por posto.
- Painel web local, usado no celular ou computador.
- Cadastro de animais com situação, data do parto e data de secagem.
- Registro de ordenhas por parciais, com destino do leite.
- Ração programada e fornecida, com medida calibrada.
- Ocorrências e intervenções.
- Lotes com histórico de alocação.
- Registro de mudanças de manejo e cálculo do efeito.
- Clima diário pela estação do INMET de Morada Nova, com sensor local condicional.
- Conciliação com o tanque ou ticket do laticínio.
- Exportação em CSV e cópia de segurança automática.

## Fora do MVP

- RFID e identificação automática.
- Dosador automático de concentrado. Teste opcional a partir do mês 4, com orçamento próprio.
- Aplicativo nativo.
- IA e previsão.
- Integração com ordenha canalizada.
- Acesso remoto ao painel pela internet.

## Premissas de segurança

- Wi-Fi WPA2 ou WPA3 com senha forte. Se o roteador permitir, uma rede só para os postos.
- Servidor local sem nenhuma porta aberta para a internet.
- Credenciais do Wi-Fi e chave de cada posto ficam na memória do ESP32, nunca no repositório.
- Cada posto tem chave própria, revogável no painel.
- Painel com PIN para alterar cadastro e apagar registros. Registro apagado vira registro anulado, nunca some.
- Sincronização com a nuvem, quando existir, só por conexão de saída.
