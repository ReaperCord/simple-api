---
inclusion: always
---

# Fonte da verdade do projeto

Fatos verificados em 11–12/10/2026. As tabelas F-APP e F-INF descrevem o repo BASE (commit `25337f2`). Depois das correções, o código ATUAL é a verdade sobre o estado do código: se divergir daqui, aponte a divergência (provavelmente já corrigida) e não reverta o código. Este arquivo só é editado pelo Leandro.

## Projeto

- Desafio técnico: Arquiteto de Cloud AWS, KXC Tecnologia. PDF em `docs/desafio-kxc.pdf` (se presente).
- Repo base: `https://github.com/SuporteKXC/simple-api`, commit `25337f2`.
- Estrutura REAL do repo (não criar pastas paralelas como `terraform/`):
  - `application/` → Node.js + Express + `pg`. Entrada: `application/src/index.js`. Start: `npm run start`.
  - `infrastructure/` → Terraform com módulos em `modules/network/*`, `modules/security/*`, `modules/ecs`. Raiz (`main.tf`, `variables.tf`, `outputs.tf`) vem VAZIA de propósito. `environments/{dev,hml,prod}.tfvars` só têm rede.
  - `infrastructure/README.md` descreve uma "arquitetura alvo" com ALB + NAT. NÃO é a nossa decisão (ver `01-arquitetura-e-restricoes.md`).
- Região: `us-east-1` (fixada nos `.tfvars`).

## Requisitos obrigatórios do desafio (PDF §3)

1. Dockerfile otimizado
2. TODA infraestrutura base via Terraform (deploy manual pelo console NÃO é avaliado)
3. Pipeline CI/CD com build + deploy automático
4. VPC nova e isolada
5. Entregáveis de arquitetura (PDF §5): diagrama com SGs e fluxo internet → banco; plano de autoscaling (métrica, min/max, thresholds, como o roteamento acompanha); DR com RPO/RTO e recriação em outra região/conta
6. README com decisões, como executar e o que ficou pendente

Diferenciais (PDF §4): API Gateway no lugar do ALB (FinOps, "desafio de ouro"), ECS/EKS, RDS, módulos Terraform, least privilege nas roles da pipeline e da aplicação.

## Fatos da aplicação (repo base)

| ID | Fato | Onde |
|---|---|---|
| F-APP-1 | Porta: `process.env.API_PORT \|\| 3000` | `application/src/index.js` |
| F-APP-2 | Rotas: `GET /` (sem banco) e `GET /connect` (`SELECT version()`) | idem |
| F-APP-3 | Cria `new Client()` por requisição, sem timeout, `client.end()` fora de `finally` | idem |
| F-APP-4 | Sem SSL no cliente `pg` | idem |
| F-APP-5 | Variáveis: `API_PORT, DB_HOST, DB_PORT, DB_DATABASE, DB_USER, DB_PASSWORD` | `application/README.md` |
| F-APP-6 | `npm audit --omit=dev` em 11/10/2026: 8 vulnerabilidades — crítica `proxy-addr`; altas `express`, `body-parser`, `path-to-regexp`; moderada `qs`; baixas `cookie`, `send`, `serve-static` | comando |
| F-APP-7 | Não existe Dockerfile nem `.dockerignore` | árvore do repo |
| F-APP-8 | `pg` 8.9 aceita `password` como função (assíncrona) e as opções `statement_timeout`, `query_timeout`, `connectionTimeoutMillis` | `node_modules/pg/lib/client.js`, `connection-parameters.js` |

## Fatos da infraestrutura (repo base)

| ID | Fato | Onde |
|---|---|---|
| F-INF-1 | SG do ALB libera 8080 e 443; listener padrão é 80/HTTP | `config/security_rules/rules-sg-alb.json`, `modules/network/listener/variables.tf` |
| F-INF-2 | SG do ECS libera ingress **8084** (app escuta 3000) | `config/security_rules/rules-sg-ecs.json` |
| F-INF-3 | SG do ECS: egress só 443 e 53 — **sem 5432** | idem |
| F-INF-4 | Placeholders: `${ALB_SG_ID}`, `${NAT_GW_ID}`, `${IGW_ID}` | `config/security_rules/*.json`, `config/routes/*.json` |
| F-INF-5 | `alb_controller_policy.json` = policy do AWS Load Balancer Controller (EKS). Errada para ECS; correta só para a service account do controller no EKS | `config/policies/` |
| F-INF-6 | Módulo `parameter-store` recebe o valor por variável → segredo vai para o tfstate | `modules/security/parameter-store/` |
| F-INF-7 | `route-table` tem `azs` default hardcoded `us-east-1a/b/c` | `modules/network/route-table/variables.tf` |
| F-INF-8 | `subnet` declara `map_public_ip_on_launch` e não usa; arquivo `ouputs.tf` (typo). Nós do EKS em subnet pública EXIGEM auto-assign de IPv4 público | `modules/network/subnet/` |
| F-INF-9 | VPC sem `enable_dns_hostnames`. Zona privada do Route 53 (namespace do Cloud Map) exige `enableDnsHostnames` e `enableDnsSupport` = true | `modules/network/vpc/main.tf` |
| F-INF-10 | ECS service sem circuit breaker, sem `service_registries`; `ignore_changes = [desired_count]` | `modules/ecs/main.tf` |
| F-INF-11 | Não existem módulos de ECR, RDS, API Gateway, Cloud Map, autoscaling, OIDC; não há bloco `terraform {}`/provider/backend | árvore do repo |
| F-INF-12 | `config/routes/private.json` cria rota default para o NAT (`${NAT_GW_ID}`) | `config/routes/private.json` |

## Fatos de serviços AWS (doc oficial, 12/10/2026)

- RDS PostgreSQL 15+: `rds.force_ssl` = 1 por padrão.
- Segredo do master gerenciado pelo RDS (`manage_master_user_password`): rotação a cada 7 dias por padrão.
- EKS: pods no Fargate só rodam em subnet privada; metrics-server não vem instalado (há community add-on); managed node group em subnet pública exige auto-assign de IPv4.
- API Gateway HTTP API + Cloud Map: a integração usa `DiscoverInstances`; ECS precisa registrar com SRV (service discovery) ou usar Service Connect. A doc não diz se há cache das descobertas.
- VPC Link V2 é imutável (subnets/SGs) e fica INACTIVE após 60 dias sem tráfego.
- `ecr:GetAuthorizationToken`, `ecs:RegisterTaskDefinition` e `ecs:DescribeTaskDefinition` não aceitam restrição por ARN (`Resource: "*"`; a doc do ECS diz que task definitions não suportam permissão por recurso).
- API Gateway, integração privada: o nome do estágio vai no caminho enviado ao backend; para tirar, `overwrite:path` = `$request.path`.
- AWS Budgets: previsão exige ~5 semanas de histórico. No Terraform, `cost_types.include_credit` vem `true` por padrão.
- RDS: snapshot cifrado com a chave KMS padrão não pode ser compartilhado com outra conta; replicação de backups automáticos para outra região dá PITR lá com RPO de minutos (custo de transferência e armazenamento).
- Terraform 1.11: trava nativa do backend S3 (`use_lockfile`) é GA; argumentos de DynamoDB depreciados.

## Medições LOCAIS já feitas (12/10/2026 — NÃO são capacidade da AWS)

CPU da API limitada por cgroup (todas as threads do Node), Postgres 16 local com SCRAM, k6 0.57, 3 séries com aquecimento, log JSON por requisição. Dados: `tests/load/results/2026-10-12-local-baseline.csv`. SLO de `/connect`: p50 ≤ 5, p95 ≤ 50, p99 ≤ 150 ms.

| Configuração | Melhor ponto (p50 / p95 / p99, medianas) | Cumpre o SLO? | Teto |
|---|---|---|---|
| `/connect` original, 0,25 vCPU | 25 req/s: 12 / 23 / 62 ms | Não (p50 > 5 ms) | ~70 req/s ("too many clients" + timeouts) |
| `/connect` pool + log, 0,25 vCPU | 400 req/s: 0,7 / 57 / 130 ms | Não (a 200 req/s o p99 estoura; a 400, o p95) | ~600 req/s |
| `/connect` pool + log, 0,5 vCPU | 1.000 req/s: 0,8 / 18 / 53 ms | Sim, até 1.000 req/s | ~1.300 req/s |
| `/connect` pool sem log, 0,25 vCPU¹ | 600 req/s: 2,5 / 81 / 139 ms | Não | ~700 req/s |
| `/` com log, 0,25 vCPU¹ | 600 req/s: 0,5 / 13 / 30 ms | Sim (SLO de `/`) | ~950 req/s |

¹ Cota aplicada só à thread principal (`tests/load/results/2026-10-12-local-mainthread-only.csv`); o controle com todas as threads mudou pouco. Uma rodada anterior (11/10, outro host, sem aquecimento nem log; saída bruta em `tests/load/results/2026-10-11-local-first-run.txt`) chegou a ~1.000 req/s com 0,25 vCPU, ~65% acima: a variação entre rodadas locais é grande.

## Conta AWS e orçamento

- Créditos: US$ 100 (confirmados no console em 11/10/2026). Até +US$ 100 por atividades no Explore AWS (US$ 20 cada: EC2, RDS, Lambda, Bedrock, Budgets).
- Free plan: nunca cobra; só serviços/recursos selecionados; fecha em 6 meses ou ao zerar créditos; EC2 elegível (contas de 15/07/2025 em diante): t3.micro, t3.small, t4g.micro, t4g.small, c7i-flex.large, m7i-flex.large.
- Paid plan: tudo liberado; cobra após os créditos.
- Conta aberta pelo cadastro novo ("Sign up for AWS (new)", liberação limitada), nos DOIS planos, até "Activate advanced AWS features": sem recursos multi-região ou cross-região, e sem GuardDuty, IAM Access Analyzer, Organizations, IAM Identity Center, Security Hub e Trusted Advisor, entre outros. Fonte: docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html
- Teto pessoal: R$ 50. Gasto planejado: ~US$ 41 de crédito (meta ≤ US$ 45).

## DESCONHECIDO (não preencha com suposição)

- **Plano da conta (Free ou Paid)** — decide tipos de nó do EKS e se a cobrança é possível
- Como a conta foi aberta (cadastro novo ou avançado) — decide se GuardDuty e recursos cross-região existem
- Data de expiração dos créditos e data de entrega do desafio
- Se o API Gateway faz cache do `DiscoverInstances` (impacta custo por requisição)
- Se o Fargate aplica a cota de CPU com throttling igual ao cgroup local
- `max_connections` real do RDS `db.t4g.micro`
- Nome do usuário/organização do fork (`<GITHUB_OWNER>`) e ID da conta (`<AWS_ACCOUNT_ID>`)
- Versão do Kubernetes em suporte padrão no momento do lab
- Preço exato do RDS `db.t4g.micro` e dos nós Spot (verificar na Pricing Calculator)
