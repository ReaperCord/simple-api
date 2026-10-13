---
inclusion: fileMatch
fileMatchPattern: ["application/**", "docker-compose*.yml", "**/Dockerfile", "**/.dockerignore"]
---

# Padrões da aplicação

## Contrato da API (não quebrar)

| Rota | Comportamento esperado |
|---|---|
| `GET /` | 200, JSON com `message: "API OK!"`, sem tocar no banco |
| `GET /connect` | 200 com `message` e `version` do Postgres; 503 com mensagem genérica se o banco falhar |
| `GET /health` | NOVA. 200 sempre que o processo está de pé (liveness). Não consulta o banco |

Variáveis existentes mantêm nome e default (`API_PORT=3000`, `DB_PORT=5432`). Novas:

| Variável | Uso | Padrão |
|---|---|---|
| `DB_POOL_MAX` | tamanho do pool (na AWS a task define 3 — regra de conexões em `01-arquitetura-e-restricoes.md`) | 5 |
| `DB_SSLMODE` | `verify-full` na AWS (TLS + verificação do certificado) ou `disable` (só local). Não usar `require`: na libpq significa "cifrar sem verificar" | `verify-full` |
| `DB_SECRET_ARN` | ARN do segredo do RDS; se presente, a senha vem do Secrets Manager e `DB_PASSWORD` é ignorada | vazio (local usa `DB_PASSWORD`) |
| `LOG_LEVEL` | nível do log | `info` |

## Correções obrigatórias (rastreie pelo ID)

| ID | Correção |
|---|---|
| A2/A3 | Um `Pool` do `pg` por processo; `connectionTimeoutMillis` 2000, `idleTimeoutMillis`, `statement_timeout` (servidor) e `query_timeout` (cliente) de 3000; sem `client.end()` manual por request |
| A4 | TLS com CA bundle da RDS quando `DB_SSLMODE=verify-full` (`rejectUnauthorized: true`). Confirmar a URL do bundle na doc da AWS e citar |
| A5 | `request_id` = `x-request-id` recebido ou UUID gerado; nunca contador global |
| A6 | Log JSON em stdout (`ts, level, msg, method, path, status, duration_ms, request_id`); nunca logar senha, string de conexão ou objeto de erro bruto do `pg`. Mantenha o log por requisição (ele custa ~15% do teto com 0,25 vCPU — medido; por isso a task tem 0,5 vCPU) |
| A7 | `SIGTERM` → `server.close()` → `pool.end()` → `exit 0`, com timeout de segurança menor que o `stopTimeout` do ECS |
| A8 | Atualizar dependências até `npm audit --omit=dev` sem CRITICAL/HIGH (a crítica atual é `proxy-addr`, transitiva do express) |
| A9 | `package.json`: `main` correto, `engines.node`, scripts `test`, `lint` |
| A10/A11 | `app.disable('x-powered-by')`, limite de payload, `/health` |
| A12 | Senha via Secrets Manager quando `DB_SECRET_ARN` existir: `password` do Pool como função assíncrona, cache ≤ 5 min, releitura em erro `28P01` (o segredo do RDS gira a cada 7 dias) |

## Testes

- Unitários com `node:test` (embutido). Não adicione framework pesado sem perguntar.
- Integração contra Postgres real (service container no CI, Compose local) com SCRAM, como no RDS.
- Toda correção acima precisa de um teste que falharia no código original.

## Dependências

Antes de adicionar qualquer pacote (inclusive `@aws-sdk/client-secrets-manager` para A12): diga nome, versão, por que é necessário e por que não dá para fazer sem ele, e espere o OK. Confirme que existe com `npm view <pkg> version`. Nunca invente nome de pacote.
