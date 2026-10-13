# ADR 0004: RDS PostgreSQL db.t4g.micro, single-AZ e privado

## Contexto

- O diferencial pedido é usar PostgreSQL no Amazon RDS em vez de um container solto. [FATO: [`infrastructure/README.md`](../../infrastructure/README.md) linha 212]
- A decisão de custo é manter o menor porte e uma única AZ, com DR por backup e PITR, sem Multi-AZ, réplicas ou Aurora. [FATO: [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) tabela "Proibido sem pedido explícito"]
- O módulo cria `aws_db_instance` com `engine = "postgres"`, `storage_type = "gp3"`, `storage_encrypted = true`, `publicly_accessible = false`, `multi_az = false`, `backup_retention_period = var.backup_retention_period` e `manage_master_user_password = true`. [FATO: [`modules/rds/main.tf`](../../infrastructure/modules/rds/main.tf) linha 31]
- O `backup_retention_period` é parametrizado por variável, com default `7` (a arquitetura alvo). [FATO: [`modules/rds/variables.tf`](../../infrastructure/modules/rds/variables.tf) variável `backup_retention_period`]
- **Restrição do Free plan**: nesta conta (Free plan) a criação do RDS com `backup_retention_period = 7` falha com `FreeTierRestrictionError: The specified backup retention period exceeds the maximum available to free tier customers`. Verificado em 2026-10-13 pelo root efêmero [`infrastructure/rds-smoke/`](../../infrastructure/rds-smoke/): com `7` o `CreateDBInstance` é recusado; com `1` o RDS é criado (apply completo em ~6m22s) e destruído sem resíduo. [FATO: `terraform apply` nos dois valores, 2026-10-13]
- O `dev` usa `db_instance_class = "db.t4g.micro"`, engine major `16`, 20 GiB de storage (`[PROPOSTA] a calibrar`), `deletion_protection = false`, `skip_final_snapshot = true` e `db_backup_retention_period = 1` (override do default 7, imposto pelo Free plan). [FATO: [`dev.tfvars`](../../infrastructure/environments/dev.tfvars)]
- O subnet group usa as duas subnets privadas, que só têm a rota local. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 186-203 e 129-134]
- O storage autoscaling fica desligado (`max_allocated_storage = 0`). [FATO: [`modules/rds/variables.tf`](../../infrastructure/modules/rds/variables.tf) linhas 39-43]
- Preço do RDS `db.t4g.micro` on-demand: cerca de US$ 0,016/h, **aproximado**, vindo da Pricing Calculator e não confirmado. A T4g Unlimited cobra US$ 0,075 por vCPU-hora acima do baseline. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Preços de referência"]
- O `max_connections` real do `db.t4g.micro` é desconhecido. A steering estima 80 a 110, a confirmar com `SHOW max_connections;`. [FATO: [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) seção "Conexões com o banco"]
- Há três alarmes mínimos: crédito de CPU, espaço livre e respostas 5xx da API, com limiares `[PROPOSTA] a calibrar`. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 361-410]

## Decisão

Usar uma instância RDS PostgreSQL `db.t4g.micro`, single-AZ, em subnets privadas, sem IP público, com storage cifrado, backups automáticos e a senha master gerenciada pelo RDS no Secrets Manager. A retenção dos backups é parametrizada (`backup_retention_period`, default 7 da arquitetura alvo); na conta Free o valor é reduzido para **1 dia**, porque o Free plan recusa 7. Ver [ADR 0011](0011-dr-via-pitr.md) para o impacto no RPO/PITR.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| RDS Multi-AZ | **A verificar**. A steering diz que "dobra" o custo da instância | Fora do orçamento. A disponibilidade em falha de AZ não é requisito do desafio |
| Aurora ou réplicas de leitura | **A verificar**. A steering diz que "triplica" | Fora do orçamento e do escopo |
| PostgreSQL em container na AWS | Custo da task, **a verificar** | A steering proíbe, e o diferencial pedido é o RDS |
| RDS em subnet pública com `publicly_accessible = true` | Igual | Contraria a regra de rede da steering (banco sem IP público) |

## Consequências

- Não há failover automático. Uma falha da instância ou da AZ derruba o banco até um restore. O plano de recuperação está em [`docs/dr.md`](../dr.md) e o [ADR 0011](0011-dr-via-pitr.md).
- No `dev` o `destroy` não deixa snapshot final (`skip_final_snapshot = true`). Combinado com o padrão do provider para backups automáticos (ver [`docs/dr.md`](../dr.md)), um `destroy` apaga os dados. A escolha evita custo residual de snapshot e vale para um laboratório. [FATO: [`dev.tfvars`](../../infrastructure/environments/dev.tfvars) linhas 84-88]
- A instância burstable pode gastar créditos de CPU. Acima do baseline a T4g Unlimited cobra crédito extra. Por isso existe o alarme `CPUCreditBalance`, e a duração dos testes de estresse deve ser anotada. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Testes de carga e custo"]
- A aplicação usa o usuário master. Um usuário com permissão só de `CONNECT` é pendência documentada. [FATO: [`03-devsecops.md`](../../.kiro/steering/03-devsecops.md) seção "Rede e banco"]
- Uma instância de teste `db.t4g.micro`, engine `16`, 20 GiB gp3, foi criada e destruída em 2026-10-13 pelo root efêmero [`infrastructure/rds-smoke/`](../../infrastructure/rds-smoke/) só para provar que o Free plan permite criar RDS e descobrir a retenção aceita (1 dia). O tamanho definitivo do storage, a versão exata do PostgreSQL (16.x), o preço real e o `max_connections` ainda **não** foram verificados na stack real.

## Status

Aceito. Decisão travada em [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md). Implementada no código, não aplicada na AWS.
