# Servidor local

Raspberry Pi 4 ou PC já existente, com PostgreSQL 16 e PostgREST. Ver `docs/06-decisoes.md`, decisão D5.

## Instalação

1. Banco em SSD, não em cartão SD comum.
2. Instalar PostgreSQL 16 e PostgREST.
3. Criar o banco e aplicar o esquema:

   ```
   createdb scara
   psql -v ON_ERROR_STOP=1 -d scara -f server/db/schema.sql
   ```

4. Rodar os testes. Eles não deixam dados no banco:

   ```
   psql -v ON_ERROR_STOP=1 -d scara -f server/db/teste.sql
   ```

5. Criar o papel de login do PostgREST, com senha forte guardada fora do repositório:

   ```sql
   create role scara_api login noinherit password '...';
   grant scara_anon, scara_operador to scara_api;
   ```

6. Gerar o segredo do token e gravar no banco:

   ```
   openssl rand -hex 32
   ```

   ```sql
   insert into scara.config_segura values ('jwt_segredo', '<segredo>');
   ```

7. Copiar `server/postgrest.conf.example` para `postgrest.conf`, preencher com o mesmo segredo e o IP da rede local.
8. Cadastrar fazenda e postos, definir o PIN do painel e gerar a chave de cada posto:

   ```sql
   insert into scara.fazenda (nome, municipio) values ('...', 'Morada Nova') returning id;
   insert into scara.posto (fazenda_id, numero) values ('<fazenda>', 1) returning id;
   select scara.definir_pin('<fazenda>', '<PIN com 6 dígitos ou mais>');
   select scara.nova_chave_posto('<posto>');
   ```

9. Gravar a chave no posto pela porta serial. Ver `firmware/posto-esp32/README.md`.

## Hora

Se a fazenda não tiver internet, instalar o módulo de relógio DS3231 no Raspberry e o `chrony` servindo a hora na rede local.
O endereço do servidor é o mesmo usado como servidor de hora no posto.

## Cópia de segurança

Diária, para o pendrive, por agendamento do sistema:

```
pg_dump -Fc scara > /mnt/pendrive/scara-$(date +%F).dump
find /mnt/pendrive -name 'scara-*.dump' -mtime +30 -delete
```

Semanal, uma cópia sai da fazenda.
Uma vez por mês, restaurar a cópia num banco de teste e rodar `teste.sql` para provar que ela funciona.

## Rede

- O servidor tem IP fixo na rede local.
- Nenhuma porta é redirecionada no roteador.
- O PostgreSQL escuta só em `127.0.0.1`.
- O PostgREST escuta só no IP da rede local.

## Mudanças no esquema

`schema.sql` é a versão inicial. Toda mudança depois da instalação vai em um arquivo novo em `server/db/migracoes/`, numerado, e `teste.sql` é atualizado junto.
