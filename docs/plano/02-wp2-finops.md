# WP2: os 5 itens de FinOps para completar o apply da stack

Data: 13/10/2026. Fonte do plan: `terraform plan` local, somente leitura (state remoto, `-lock=false`, `dev.tfvars`, `image_tag=ddbdd7d7…`). Preços: só da tabela de `.kiro/steering/02-finops-guardrails.md`; o que não está lá vai como "a verificar".

## 1. O que muda (plan: 17 to add, 0 to change, 1 to destroy)

| Grupo | Recursos |
|---|---|
| API Gateway | VPC Link V2, integração, rota `$default`, estágio `$default` |
| Cloud Map | namespace privado (cria zona privada do Route 53), serviço SRV |
| ECS | task definition (revisão inicial), service |
| Auto scaling | scalable target, policy de CPU 60% (cria 2 alarmes `TargetTracking-*`) |
| RDS | instância `db.t4g.micro` (senha gerenciada, cria segredo); **DB subnet group é recriado** (destroy + add; estava *tainted* pelo apply que falhou; recurso vazio e sem custo) |
| IAM | policy e attachment da `task_role` |
| CloudWatch | 3 alarmes (`rds_cpu_credit_balance`, `rds_free_storage`, `api_5xx`) |
| Leitura | `data.aws_iam_policy_document.task` |

Já existem e não mudam: VPC, subnets, rotas, IGW, 3 SGs, cluster ECS, HTTP API, log group, role de execução.

## 2. Custo por hora e por mês

| Recurso | Por hora | Por mês (730 h) | Fonte |
|---|---|---|---|
| Fargate ARM64 0,5 vCPU / 1 GB (1 task) | US$ 0,0198 | US$ 14,42 | tabela de 02-finops (US$ 0,03238/vCPU-h + US$ 0,00356/GB-h) |
| IPv4 público da task | US$ 0,005 | US$ 3,65 | tabela de 02-finops |
| RDS `db.t4g.micro` | ~US$ 0,016 | ~US$ 11,7 | **aproximado** (Pricing Calculator); storage gp3 20 GiB: **a verificar** |
| Cloud Map (1 recurso registrado) | — | US$ 0,10 | tabela de 02-finops |
| Zona privada do Route 53 | — | US$ 0,50 | tabela de 02-finops |
| API Gateway HTTP API | — | US$ 1,00 por milhão de requisições | tabela de 02-finops |
| VPC Link V2, segredo do RDS, 5 alarmes, logs | — | **a verificar** | sem linha na tabela; checar nas páginas de preço de cada serviço |

Total de referência: ~US$ 0,041/h só com task + IPv4 + RDS (≈ US$ 30/mês 24x7; o doc fala em ~US$ 34/mês com o resto). Crédito restante: US$ 140 (`get-account-plan-state`, 13/10).

## 3. O que continua cobrando depois do `destroy`

- Bootstrap (não é destruído): bucket de state, ECR (3 manifests de imagem; storage **a verificar**, centavos), budget (gratuito).
- Task definitions: as revisões ficam ACTIVE por causa do `skip_destroy = true`; não cobram.
- RDS: `skip_final_snapshot = true` e backups automáticos somem com a instância; sem snapshot residual esperado. O segredo é apagado junto com a instância (doc RDS). Confirmar com `tools/residual-check.sh`.
- Log group `/ecs/simple-api-dev` é do Terraform e sai no destroy.

## 4. Por quanto tempo ligado

Proposta: uma janela de até 6 h (apply, smoke, `deploy.yml`, evidências e carga curta), seguida de destroy no mesmo dia. 6 h × ~US$ 0,041 ≈ US$ 0,25 mais requisições. Quem decide é o Leandro. Carga na AWS (WP4) pede cálculo e aprovação próprios antes.

## 5. O Free plan aceita criar isso?

DESCONHECIDO para parte dos serviços.
- Provado nesta conta: RDS `db.t4g.micro` postgres 16 (com `backup_retention_period = 1`), cluster ECS e HTTP API.
- Não provado: service Fargate, VPC Link V2, namespace do Cloud Map e zona privada do Route 53.
- Mitigação: se o plano recusar algum, o apply falha naquele recurso e o que já foi criado continua no state; o destroy limpa. Sem custo relevante enquanto o RDS e a task não existirem.
