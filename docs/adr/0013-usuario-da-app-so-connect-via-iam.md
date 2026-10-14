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
- **Risco de memória no `db.t4g.micro`:** a doc da AWS indicava 300 a 1000 MiB extras; medido na AWS: ~117 MiB de RAM e ~150 MiB de swap (ver "Validação na AWS"). Se a margem não bastar, voltar a `db_iam_auth = false` (modo senha) ou subir a classe.
- Limite de conexões novas por segundo com IAM: não consultei o número (**a verificar** na doc do RDS); o pool de 3 conexões por task reaproveita conexões, então o impacto esperado é baixo.

## Validação na AWS (14/10/2026)

Evidências em `tests/load/results/2026-10-14-aws-iam-auth-validacao.txt` e `…-rds-metricas-iam-vs-senha.csv`; análise em [`docs/performance/benchmark-aws.md`](../performance/benchmark-aws.md).

- **Funciona:** apply de 54 recursos, `db-init` (idempotente; `app_connect` com só `rds_iam` e `CONNECT`), `/connect` = 200 com token IAM, `deploy.yml` verde com smoke.
- **Menor privilégio comprovado:** a role da API não lê o segredo master (`implicitDeny`) e conecta só como `app_connect` nesta instância; como `app_connect`, criar tabela, schema ou role, ler `pg_authid`/`pg_shadow` e `SET ROLE` do master foram negados (`42501`).
- **Estável:** 2 h de soak a 600 req/s com 0% de erro e sem deriva de latência.
- **O risco de memória se confirmou, e a causa foi provada por A/B na mesma instância:** a autenticação IAM custa ~117 MiB de RAM e ~150 MiB de swap no `db.t4g.micro` (memória livre 152 a 184 MiB → 52 a 68 MiB; swap 0,5 → 134 a 201 MiB (médias de 5 min); créditos de CPU em ~0). Sem cobrança extra de créditos excedentes na janela, sem erro, mas **com a margem fina**.
- **Dois comportamentos para saber:** (1) a primeira conexão fria pode estourar o `connectionTimeoutMillis` de 2 s (geração do token e TLS), dando um 503 pontual (mitigado pelo pré-aquecimento da partida, ainda sem medição na AWS); (2) depois de **ligar** a autenticação IAM numa instância existente, as conexões ficam lentas por ~1 min.
- **DR:** o `DbiResourceId` muda na instância restaurada, então a policy `rds-db:connect` precisa ser atualizada (4 s por CLI; medido em [`docs/dr.md`](../dr.md)).

### Opções para a instância (decisão do Leandro)

| Opção | Prós e contras |
|---|---|
| Manter IAM no `db.t4g.micro` (como está) | Usuário sem senha e só `CONNECT`; funciona e é estável no laboratório; margem de memória fina e créditos de CPU zerados |
| IAM em instância maior (ex.: `db.t4g.small`, 2 GiB) | Recupera a folga de memória; custo maior (preço **a verificar**; a tabela de FinOps só traz o do micro) |
| Voltar ao modo senha (`db_iam_auth = false`) | Sem custo de memória; a app volta a usar o usuário master |

Recomendação: **manter IAM no micro** para a entrega (mostra least privilege até o banco, sem custo extra e com estabilidade medida), documentando o trade-off, e propor o `db.t4g.small` se a carga real exigir folga.

## Status

Aceito. Implementado, coberto por testes (75 na app, `terraform test` do módulo `rds`, testes dos scripts) e **validado na AWS em 14/10/2026** (seção acima). **Decisão do Leandro em 14/10/2026: manter a autenticação IAM no `db.t4g.micro`** (a primeira opção da tabela), com o trade-off de memória documentado; subir a classe só se a carga real exigir folga.

**Mitigação aplicada:** a app aquece o token e a primeira conexão do pool na partida (`application/src/prewarm.js`, só no modo IAM), sem bloquear a partida nem derrubar o processo se falhar. Isso ataca o 503 pontual da primeira conexão fria; **não foi medido na AWS** (valida no próximo apply).
