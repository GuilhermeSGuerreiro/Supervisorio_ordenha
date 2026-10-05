# Escopo do piloto

## Contexto

- Ordenha balde ao pé, 3 vacas por vez, 3 baldes separados acionados por vácuo.
- Cada balde acumula o leite de várias vacas e é esvaziado antes de atingir o limite operacional.
- As vacas comem concentrado durante a ordenha.
- Piloto na fazenda de um familiar, em Morada Nova-CE, financiado por etapa.
- Objetivo posterior: produto para produtores de Morada Nova e região. O município é o maior produtor de leite do Ceará, com 117,3 milhões de litros em 2025 segundo a Pesquisa da Pecuária Municipal do IBGE.

## Perguntas que o MVP responde

| Pergunta | Dado que responde |
|---|---|
| Quanto cada vaca produziu? | Soma das parciais da ordenha, por turno e por dia |
| Quanto concentrado foi fornecido? | Medidas lançadas convertidas para kg, marcadas como conferidas ou estimadas |
| Qual animal mudou e merece atenção? | Queda em relação à média da própria vaca no mesmo turno, ocorrências |
| Como produção e gasto evoluem? | Série diária de leite e concentrado por vaca e do rebanho, kg de leite por kg de concentrado |

## Dentro do MVP

- Balança por posto com ESP32 e envio por Wi-Fi local.
- Botão físico e LED por posto.
- Painel web local, usado no celular ou computador.
- Cadastro de animais com situação, data do parto e data de secagem.
- Registro de ordenhas por parciais, com destino do leite.
- Ração programada e fornecida, com medida calibrada.
- Ocorrências e intervenções.
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
