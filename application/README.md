# simple-api

## Descrição
Uma API em Node.js utilizando o Express Framework que realiza a conexão com um banco de dados PostgreSQL.

## Como utilizar
O comando para iniciar a API é **npm run start**

Requer Node 24 (`engines.node` = `>=24 <25`). Testes: `npm test` (unitários) e `npm run test:int` (integração, ver abaixo). Lint: `npm run lint`.

## Rotas
| Rota | Método | Descrição |
| --- | --- | --- |
/ | GET | Retorna uma mensagem estática (`API OK!`) e o `request_id`.
/connect | GET | Realiza a conexão com o banco e retorna a versão da engine. Se o banco falhar, responde 503 com mensagem genérica.
/health | GET | Liveness: responde 200 `{"status":"ok"}` enquanto o processo está de pé. Não consulta o banco.

Toda resposta traz o header `x-request-id` (o valor recebido, se casar `^[A-Za-z0-9._:-]{1,128}$`, ou um UUID gerado).


## Variáveis de Ambiente
| Nome | Description  | Padrão |
| --- |  --- |  --- |
API_PORT | Port da API Node | 3000
DB_DATABASE | Database do banco de dados | 
DB_HOST | Endereço do banco de dados | 
DB_PORT | Port do banco de dados | 5432
DB_USER | Usuário do banco de dados | 
DB_PASSWORD | Senha do banco de dados. Obrigatória quando `DB_SECRET_ARN` não está definido; ignorada quando está | 
DB_POOL_MAX | Tamanho do pool de conexões (inteiro de 1 a 20) | 5
DB_SSLMODE | `verify-full` (TLS verificando o certificado) ou `disable` (só uso local). Outro valor (inclusive `require`) faz o processo falhar na partida | verify-full
DB_SSL_CA_FILE | Caminho do CA bundle da RDS. Obrigatório com `DB_SSLMODE=verify-full` (bundle: https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem) | 
DB_SECRET_ARN | ARN do segredo do RDS no Secrets Manager (JSON com o campo `password`). Se definido, a senha vem dele, com cache de 5 min e releitura ao receber erro `28P01` | 
LOG_LEVEL | Nível do log JSON em stdout: `debug`, `info`, `warn` ou `error` | info
SHUTDOWN_TIMEOUT_MS | Tempo máximo do encerramento ordenado após SIGTERM/SIGINT; passado esse tempo o processo sai com código 1 | 8000

## Testes de integração
`npm run test:int` roda contra um Postgres real (SCRAM) e é ignorado sem `INTEGRATION_DB_HOST`. Variáveis: `INTEGRATION_DB_HOST`, `INTEGRATION_DB_PORT` (5432), `INTEGRATION_DB_USER`, `INTEGRATION_DB_PASSWORD`, `INTEGRATION_DB_DATABASE`.
