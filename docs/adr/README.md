# Architecture Decision Records

Cada ADR registra uma decisão de arquitetura do projeto, com contexto (fatos e fontes), decisão, alternativas com custo quando existe fonte, consequências e status. As decisões vêm de [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) e estão travadas: não são reabertas sem pedido explícito.

Convenções usadas nos ADRs:

- `[FATO: fonte]` foi lido no repositório, num comando ou numa URL citada. `[HIPÓTESE]` é inferência não confirmada. `[PROPOSTA]` é recomendação.
- Preços vêm só da tabela de [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md). O que não está lá aparece como **a verificar**.
- Números de desempenho são do benchmark **LOCAL** e não valem como capacidade da AWS.
- "Implementado" quer dizer que existe no código e passa `terraform validate` e `terraform test` no CI. Nenhuma decisão foi aplicada na AWS.

| ADR | Decisão | Status |
|---|---|---|
| [0001](0001-api-gateway-http-api-no-lugar-de-alb.md) | API Gateway HTTP API no lugar de ALB | Aceito, implementado, não aplicado |
| [0002](0002-vpc-link-v2-e-cloud-map-srv.md) | VPC Link V2 com Cloud Map e registro SRV | Aceito, implementado, não aplicado |
| [0003](0003-ecs-fargate-arm64-0-5-vcpu-1-gb.md) | ECS Fargate ARM64 com 0,5 vCPU e 1 GB, baseado no benchmark LOCAL | Aceito, implementado, não validado na AWS |
| [0004](0004-rds-postgresql-db-t4g-micro-single-az-privado.md) | RDS PostgreSQL db.t4g.micro, single-AZ e privado | Aceito, implementado, não aplicado |
| [0005](0005-sem-nat-tasks-em-subnet-publica.md) | Sem NAT Gateway, tasks em subnet pública com SG restrito | Aceito, implementado, não aplicado |
| [0006](0006-tls-verify-full-e-segredo-gerenciado-pelo-rds.md) | TLS verify-full e segredo gerenciado pelo RDS com rotação de 7 dias | Aceito, implementado, não validado contra a AWS |
| [0007](0007-eks-somente-como-laboratorio-efemero.md) | EKS somente como laboratório efêmero | Aceito como desenho, não implementado |
| [0008](0008-terraform-com-roots-separados.md) | Terraform com roots separados (bootstrap, principal e eks-lab) | Aceito, `eks-lab` não implementado |
| [0009](0009-pipeline-com-oidc-e-um-environment-por-workflow.md) | Pipeline com OIDC e um environment por workflow | Aceito, implementado, não executado |
| [0010](0010-regras-de-sg-por-chaves-simbolicas.md) | Regras de SG por chaves simbólicas em vez de `templatefile()` | Aceito, implementado e coberto por `terraform test` |
| [0011](0011-dr-via-pitr.md) | Recuperação de desastre por backups automáticos e PITR | Aceito como plano, não implementado e não testado |
| [0012](0012-divergencia-da-arquitetura-alvo.md) | Divergência consciente da arquitetura alvo (ALB e NAT) | Aceito, implementado, não aplicado |
| [0013](0013-usuario-da-app-so-connect-via-iam.md) | Usuário da app só com CONNECT, via autenticação IAM do RDS | Aceito, implementado e validado na AWS (14/10/2026); decidido manter IAM no `db.t4g.micro` |

## Outros documentos de arquitetura

- [`docs/arquitetura.md`](../arquitetura.md): diagrama, security groups, portas e fluxo da internet até o banco.
- [`docs/autoscaling.md`](../autoscaling.md): métrica, alvo, limites, roteamento e o que não foi validado.
- [`docs/dr.md`](../dr.md): RPO e RTO, restore e recriação em outra região ou conta.
- [`docs/performance/benchmark-local.md`](../performance/benchmark-local.md): resumo dos CSV do benchmark LOCAL.
