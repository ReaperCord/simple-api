# Usuário do banco só com CONNECT (autenticação IAM): runbook

Decisão e riscos: [ADR 0013](adr/0013-usuario-da-app-so-connect-via-iam.md). Estado: implementado e **validado na AWS em 14/10/2026** (ver a seção "Validação na AWS" do ADR). Custo medido no `db.t4g.micro`: ~117 MiB de RAM e ~150 MiB de swap.

## Como funciona

```text
API (task role: rds-db:connect só em app_connect)
   │  token IAM (15 min, cache de 5 min)  ──►  RDS (usuário app_connect, role rds_iam, só CONNECT)
   └─ DB_AUTH_MODE=iam, DB_USER=app_connect, TLS verify-full

db-init (task efêmera, role própria com GetSecretValue no segredo master)
   └─ cria/confirma app_connect com a credencial master; confere os privilégios reais
```

## Ligar (já é o padrão do `dev`)

`infrastructure/environments/dev.tfvars`: `db_iam_auth = true` e `db_app_username = "app_connect"`. Com `false`, tudo volta ao modo anterior (master e segredo gerenciado), sem a role e a task definition do `db-init`.

## Sequência em uma janela de AWS

0. **Publicar a imagem nova antes do apply**: a imagem do ECR de antes desta mudança não conhece `DB_AUTH_MODE=iam` e cairia em erro de configuração. Depois do merge, `deploy.yml` com `only_build=true` (workflow_dispatch) publica a tag do novo commit; use esse SHA como `image_tag` do `infra.yml`.
1. `infra.yml apply` (cria o RDS com `iam_database_authentication_enabled`, a role `…-dbinit` e a task definition `…-dbinit`). O service sobe, `/` e `/health` respondem, **`/connect` responde 503** (o usuário ainda não existe).
2. **Uma vez**, com o perfil de escrita (`kxc-admin`) e aprovação: `tools/run-db-init.sh dev`. A saída traz uma linha `DBINIT {...}` com `"ok":true` e os privilégios que o banco realmente concede. Idempotente.
3. `GET /connect` = 200. Só então o `deploy.yml` (o smoke dele exige `/connect` = 200).
4. Acompanhar `FreeableMemory` do RDS durante os testes (risco do ADR 0013).

## Verificações que a janela deve fazer

- `/connect` = 200 com a task role **sem** acesso ao segredo (`aws iam simulate-principal-policy` ou tentar `GetSecretValue` com a role: deve negar).
- Tentar, com o usuário `app_connect`, criar uma tabela ou ler dados de outro schema: deve falhar.
- Derrubar a task e confirmar que a nova também conecta (token novo).
- Comparar `FreeableMemory` antes e depois do primeiro `/connect`.

## Comportamentos medidos na validação

- A **primeira** conexão fria depois de criar o usuário pode dar um 503 pontual (2,0 s = `connectionTimeoutMillis`); a seguinte funciona. A app agora **pré-aquece** o token e a primeira conexão na partida (`src/prewarm.js`); o efeito ainda não foi medido na AWS. Se o `db-init` ainda não rodou, o pré-aquecimento falha com um aviso e a app segue de pé.
- Depois de **ligar** a autenticação IAM numa instância já no ar, o `/connect` fica indisponível por ~1 min.
- O `tools/run-db-init.sh` já roda sem erro no Git Bash (corrigido o `MSYS_NO_PATHCONV`).

## Quando algo falha

| Sintoma | Causa provável |
|---|---|
| `/connect` 503 logo após o apply | O `db-init` ainda não rodou |
| `DBINIT_ERRO` com `code` `28P01` | O token foi recusado: a role da task não tem `rds-db:connect` no usuário e instância certos, ou o usuário não é membro de `rds_iam` |
| `DBINIT_ERRO` sobre `rds_iam` | A instância foi criada sem `iam_database_authentication_enabled` |
| `DBINIT {"ok":false,...}` | O banco concedeu mais do que CONNECT (ver `privileges` na linha); investigar antes de seguir |
| Instância lenta ou com pouca memória livre | Custo de memória da autenticação IAM no `db.t4g.micro`: voltar a `db_iam_auth = false` |
