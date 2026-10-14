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
DB_AUTH_MODE | `password` (padrão: `DB_PASSWORD` ou `DB_SECRET_ARN`) ou `iam` (autenticação IAM do RDS: a "senha" é um token gerado com `@aws-sdk/rds-signer`, cache de 5 min e renovação em `28P01`). No modo `iam`, `DB_HOST`, `DB_USER`, `DB_SSLMODE=verify-full` e `AWS_REGION` são obrigatórios e `DB_SECRET_ARN`/`DB_PASSWORD` são recusados. Ver [`docs/usuario-db-iam.md`](../docs/usuario-db-iam.md) | password
AWS_REGION | Região do RDS para gerar o token; só no modo `iam` (também lê `AWS_DEFAULT_REGION`) | 
DB_APP_USER | Só para `node src/db-init.js`: nome do usuário a criar (minúsculas, dígitos e `_`) | 
LOG_LEVEL | Nível do log JSON em stdout: `debug`, `info`, `warn` ou `error` | info
SHUTDOWN_TIMEOUT_MS | Tempo máximo do encerramento ordenado após SIGTERM/SIGINT; passado esse tempo o processo sai com código 1 | 8000

## Testes de integração
`npm run test:int` roda contra um Postgres real (SCRAM) e é ignorado sem `INTEGRATION_DB_HOST`. Variáveis: `INTEGRATION_DB_HOST`, `INTEGRATION_DB_PORT` (5432), `INTEGRATION_DB_USER`, `INTEGRATION_DB_PASSWORD`, `INTEGRATION_DB_DATABASE`.
