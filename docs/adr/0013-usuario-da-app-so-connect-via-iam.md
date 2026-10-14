# ADR 0013: usuário da app só com CONNECT, via autenticação IAM do RDS

## Contexto

- Até aqui a app conectava como o usuário **master** do banco (`DB_USER = simple_api`), lendo a senha gerenciada do Secrets Manager. A steering aceitava isso para o laboratório e listava "usuário só com `CONNECT`" como pendência documentada. [FATO: [`03-devsecops.md`](../../.kiro/steering/03-devsecops.md) seção "Rede e banco"]
- A app só executa `SELECT version()` e `SELECT 1`; não precisa de nenhum privilégio no banco além de conectar. [FATO: [`application/src/app.js`](../../application/src/app.js)]
- Autenticação IAM do RDS: o usuário do banco recebe a role `rds_iam` e entra com um **token** (URL assinada, vida de 15 minutos) no lugar de senha; a permissão fica na IAM (`rds-db:connect` no ARN `arn:aws:rds-db:<região>:<conta>:dbuser:<DbiResourceId>/<usuário>`). Para PostgreSQL: `CREATE USER x; GRANT rds_iam TO x;`. [FATO: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html e `…DBAccounts.html`, abertas em 14/10/2026]
- Limitação citada pela doc: a autenticação IAM exige **300 a 1000 MiB de memória extra** na instância, e para classes burstable recomenda reduzir buffers e cache. O `db.t4g.micro` tem 1 GiB. [FATO: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html, "Limitations", aberta em 14/10/2026] Também: para PostgreSQL, quem recebe `rds_iam` passa a entrar só por IAM (inclusive o master, se o recebesse). [FATO: mesma página]
- O SDK oficial para gerar o token em JavaScript é `@aws-sdk/rds-signer`, classe `Signer` com `getAuthToken()`. [FATO: tipos do pacote 3.1150.0, `dist-types/Signer.d.ts`]

## Decisão

1. A app tem um modo `DB_AUTH_MODE=iam`: gera o token com `@aws-sdk/rds-signer` (cache de 5 min, invalidado em erro `28P01`, mesma interface do provedor de segredo) e entra como um usuário **`app_connect`**, sem senha, com `DB_SSLMODE=verify-full` obrigatório. O modo padrão continua `password` (nada muda para quem não ligar).
2. O usuário é criado **uma vez**, de forma idempotente, por `src/db-init.js` (rodado como task efêmera por `tools/run-db-init.sh`) com a credencial master. O script concede só `rds_iam` e `CONNECT`, e **confere o que o banco realmente concede** (sem superuser, createdb, createrole, replication, bypassrls, sem CREATE no banco nem no schema `public`); se algo vier a mais, sai com erro.
3. No Terraform, `db_iam_auth = true` (dev) liga `iam_database_authentication_enabled` no RDS, troca a policy da task role de `secretsmanager:GetSecretValue` por `rds-db:connect` **só nesse usuário e nessa instância** e cria uma role e uma task definition **separadas** para o `db-init` (a role da API não tem acesso ao segredo master). O master e o segredo gerenciado continuam existindo e rotacionando, mas a API não os usa.
4. A escolha vale desde o primeiro apply: o service ignora mudanças de task definition (`ignore_changes`), então trocar o modo depois exige uma nova revisão pelo pipeline.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| Segundo segredo no Secrets Manager com senha do usuário restrito | US$ 0,40/mês por segredo (**a verificar** na página de preços) e rotação própria | A senha teria de ser gerada fora do Terraform (senão vai para o state) e girada por conta própria; mais partes móveis que a autenticação IAM |
| `random_password` no Terraform | zero | Coloca a senha no tfstate, violando a regra de segredo fora do state (03-devsecops.md) |
| Provider `postgresql` no Terraform para criar o usuário | zero | O RDS é privado e o runner do GitHub não tem rota até ele |
| Manter o master na app (status anterior) | zero | A app teria privilégio total no banco sem precisar dele |

## Consequências

- **Dependência nova:** `@aws-sdk/rds-signer` fixada em `3.1150.0` (mesma versão do `@aws-sdk/client-secrets-manager` que a app já usa; Apache-2.0; `npm audit --omit=dev` com 0 vulnerabilidades). A steering pede OK do Leandro antes de adicionar pacote; o pedido foi descrito na conversa de 14/10/2026 e confirmado com "pode seguir" (interpretação registrada aqui para ser revista).
- **Passo manual novo no runbook:** depois do `infra.yml apply`, rodar `tools/run-db-init.sh` uma vez. Até lá a rota `/connect` responde 503 e o smoke do `deploy.yml` falha ([`docs/usuario-db-iam.md`](../usuario-db-iam.md)).
- O token não é registrado em CloudWatch/CloudTrail (limitação da AWS), então o diagnóstico de falha de autenticação depende do log da app (que só registra `name` e `code`).
- **Risco de memória no `db.t4g.micro`:** a doc da AWS indica 300 a 1000 MiB extras. **Não validado na AWS**; a primeira janela com `db_iam_auth = true` deve acompanhar `FreeableMemory` do RDS e o `/connect` sob carga. Se não couber, o plano é voltar a `db_iam_auth = false` (modo senha, comportamento anterior).
- Limite de conexões novas por segundo com IAM: não consultei o número (**a verificar** na doc do RDS); o pool de 3 conexões por task reaproveita conexões, então o impacto esperado é baixo.

## Status

Aceito. Implementado no código e coberto por testes unitários (72 testes na app, `terraform test` do módulo `rds`, testes dos scripts), com `terraform validate` e `plan` (54 recursos) limpos. **Não aplicado nem validado na AWS.**
