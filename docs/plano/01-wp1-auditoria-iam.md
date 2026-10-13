# WP1: auditoria da policy `gha-infra` contra os recursos que faltam criar

Data: 13/10/2026. Escopo: `data "aws_iam_policy_document" "infra"` e `"infra_iam_state"` em `infrastructure/modules/oidc/main.tf` versus os recursos da stack (ecs, rds, cloudmap, apigw, autoscaling, alarmes, roles da task). Só leitura; nada foi alterado no código nem na AWS.

## Resultado

Nenhum patch novo é necessário. O `boot.tfplan` atual (policy já mergeada em `aa2616e`) basta para o WP0.

| # | Ponto | Status | Evidência |
|---|---|---|---|
| 2.1 | `ecs:DeregisterTaskDefinition` no destroy | ✅ NÃO NECESSÁRIA | `aws_ecs_task_definition` tem `skip_destroy = true` (`infrastructure/modules/ecs/main.tf`). Doc do provider: skip_destroy = "retain the old revision when the resource is destroyed or replacement is necessary". Logo o destroy não desregistra. Efeito colateral: revisões ficam ACTIVE após o destroy (sem custo; o `residual-check.sh` não olha task definitions). Mesmo que a doc esteja errada, o erro cairia na task definition e nos recursos que dependem dela (roles, log group); RDS, API Gateway e service já teriam sido destruídos. |
| 2.4 | RDS com senha gerenciada | ✅ Policy já cobre | Doc RDS + Secrets Manager: o chamador precisa de `kms:DescribeKey`, `secretsmanager:CreateSecret`, `secretsmanager:TagResource`; `kms:CreateGrant`, `Decrypt` e `GenerateDataKey` só com chave gerenciada pelo cliente (não é o caso: usamos a chave padrão). Statement `RdsManagedSecret` tem as três. A doc diz que ao apagar a instância o segredo é apagado junto. |
| — | Application Auto Scaling (ECS) | ✅ | Doc: o chamador precisa de `ecs:DescribeServices`, `ecs:UpdateService`, `cloudwatch:DescribeAlarms`, `PutMetricAlarm`, `DeleteAlarms` e das ações `application-autoscaling:*` de target/policy. Todas presentes. |
| — | Nomes de alarmes e roles | ✅ | Alarmes `${local.name}-...` = `simple-api-dev-...` casam com `alarm:simple-api-*`; roles `simple-api-dev-ecs-exec/-ecs-task` e policies `...-policy` casam com `role/policy simple-api-*`. |
| 2.2 | Integração API GW + Cloud Map e `CreateService` com `service_registries` | ⚠️ NÃO VERIFICÁVEL AGORA | A doc de integração privada confirma que o API Gateway usa `DiscoverInstances`, mas não lista permissões do chamador. Observar no apply: se der AccessDenied, ler a ação no log. |
| — | Criação do VPC Link V2 (ENIs/EC2) | ⚠️ NÃO VERIFICÁVEL AGORA | Não achei a lista de permissões do chamador. Observar no apply. |
| — | Escopo de `kms:DescribeKey` (`key/*`) para a chave `aws/secretsmanager` | ⚠️ NÃO VERIFICÁVEL AGORA | Só se confirma no `CreateDBInstance`. |

## Decisão para o Leandro

- Aplicar o `boot.tfplan` agora (WP0) e seguir para o WP2. Os ⚠️ ficam como risco conhecido: se aparecer AccessDenied, o ciclo é o de sempre (ler a ação, patch com comentário em `modules/oidc/main.tf`, branch, merge `--no-ff`, reaplicar o bootstrap, rodar o apply de novo).
- Não adicionar `ecs:DeregisterTaskDefinition` (least privilege; ver 2.1).
