# ADR 0006: TLS verify-full e segredo gerenciado pelo RDS com rotação de 7 dias

## Contexto

- O código base não usava SSL no cliente `pg`, criava uma conexão por requisição e recebia a senha por variável. [FATO: F-APP-3, F-APP-4 em [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md)]
- No RDS PostgreSQL 15 ou superior, `rds.force_ssl` vem como 1 por padrão. O segredo do master gerenciado pelo RDS gira a cada 7 dias por padrão. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Fatos de serviços AWS", doc oficial de 12/10/2026]
- O módulo `parameter-store` do repositório base recebe o valor por variável, então o segredo iria para o tfstate. [FATO: F-INF-6 em [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md)]
- No Terraform, `manage_master_user_password = true`, sem `password`, mantém a senha fora do state. [FATO: [`modules/rds/main.tf`](../../infrastructure/modules/rds/main.tf) linhas 18-20]
- Na aplicação:
  - `DB_SSLMODE` aceita só `verify-full` ou `disable`, com `verify-full` como padrão, e exige `DB_SSL_CA_FILE` nesse modo. [FATO: [`application/src/config.js`](../../application/src/config.js) linhas 3-4 e 29-38]
  - Com `verify-full` o pool usa o CA bundle e `rejectUnauthorized: true`. [FATO: [`application/src/db.js`](../../application/src/db.js) linhas 29-31]
  - Com `DB_SECRET_ARN`, a senha é uma função assíncrona que lê o Secrets Manager, com cache de 5 minutos. Em erro `28P01` o cache é invalidado e a consulta é repetida uma vez. [FATO: [`application/src/secret.js`](../../application/src/secret.js) linhas 3 e 30-43 e [`application/src/db.js`](../../application/src/db.js) linhas 49-60]
  - A dependência `@aws-sdk/client-secrets-manager` está fixada em `3.1150.0`. [FATO: [`application/package.json`](../../application/package.json) linha 3]
- Na imagem, o CA bundle global da RDS é baixado com `ADD --checksum`. A AWS não publica checksum do bundle, então o hash SHA-256 foi medido localmente em 12/10/2026 (confiança no primeiro uso, TOFU). [FATO: [`application/Dockerfile`](../../application/Dockerfile) linhas 5-10 e 28-29]
- Na AWS a task define `DB_SSLMODE=verify-full`, `DB_POOL_MAX=3` e `DB_SECRET_ARN`, sem senha em variável de ambiente. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 318-329]
- Permissões: a task role lê o segredo (`secretsmanager:GetSecretValue`) só no ARN do segredo do RDS. A execution role não acessa segredos. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 239-277]

## Decisão

Exigir TLS com verificação do certificado (`verify-full`) entre a aplicação e o RDS e usar o segredo do master gerenciado pelo RDS, com rotação padrão de 7 dias. A aplicação lê a senha do Secrets Manager ao abrir conexão e trata a rotação.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| `secrets[].valueFrom` na task definition | **A verificar** (custo do segredo no Secrets Manager não está na tabela da steering) | A injeção estática não trata a rotação de 7 dias: a senha da task envelhece |
| Módulo `parameter-store` com senha por variável | Sem custo adicional conhecido | O segredo entraria no tfstate (F-INF-6) |
| `sslmode=require` | Igual | Na libpq significa cifrar sem verificar o certificado. A aplicação rejeita esse valor na partida |
| Senha em variável de ambiente da task | Igual | Proibido em [`03-devsecops.md`](../../.kiro/steering/03-devsecops.md) |

## Consequências

- Há uma chamada ao Secrets Manager na primeira conexão e a cada 5 minutos. Como não há VPC endpoint, essa chamada sai pela internet em 443. [HIPÓTESE: o custo por chamada e o impacto na latência não foram medidos]
- Logo após uma rotação pode haver uma consulta com falha antes da releitura. O código repete uma vez. [FATO: [`db.js`](../../application/src/db.js) linhas 53-57]
- O Dockerfile quebra o build de propósito se a AWS atualizar o bundle: é preciso conferir a mudança e atualizar o hash. O primeiro build no runner do CI serve de segunda medição do hash, segundo o comentário do passo de build. O resultado desse run não foi reverificado neste turno. [FATO: [`ci.yml`](../../.github/workflows/ci.yml) linhas 99-102]
- A aplicação usa o usuário master. Um usuário com permissão só de `CONNECT` é pendência documentada. [FATO: [`03-devsecops.md`](../../.kiro/steering/03-devsecops.md) seção "Rede e banco"]
- **Não verificado:** TLS `verify-full` contra um RDS real, `GetSecretValue` real, o formato do segredo (campo `password` em JSON) e a rotação de senha na prática. Os testes cobrem essa lógica com doubles. [FATO: [`application/test/secret.test.js`](../../application/test/secret.test.js)]

## Status

Aceito. Regra de segurança em [`03-devsecops.md`](../../.kiro/steering/03-devsecops.md). Implementado no código da aplicação e do Terraform, não validado contra a AWS.
