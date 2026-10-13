# ADR 0003: ECS Fargate ARM64 com 0,5 vCPU e 1 GB, baseado no benchmark LOCAL

## Contexto

- A aplicação é uma API Node.js que, em `/connect`, abre uma consulta no PostgreSQL. A task roda no ECS Fargate. [FATO: [`application/src/app.js`](../../application/src/app.js) linhas 55-79]
- O benchmark foi feito **localmente** em 12/10/2026, numa VM de 2 vCPUs com CPU limitada por cgroup, Postgres 16 local com SCRAM, k6 0.57 e três séries por ponto. **Não é capacidade da AWS.** [FATO: [`tests/load/local-baseline/README.md`](../../tests/load/local-baseline/README.md)]
- Resultado resumido, conferido contra os CSV em [`docs/performance/benchmark-local.md`](../performance/benchmark-local.md) (medianas das três séries, LOCAL):

| Configuração (LOCAL) | Melhor ponto (p50 / p95 / p99, ms) | SLO de `/connect` (p50 ≤ 5, p95 ≤ 50, p99 ≤ 150) |
|---|---|---|
| Pool e log, 0,25 vCPU, 200 req/s | 1,06 / 37,81 / 186,43 | Não cumpre (p99 acima de 150) |
| Pool e log, 0,25 vCPU, 400 req/s | 0,68 / 56,69 / 129,78 | Não cumpre (p95 acima de 50) |
| Pool e log, 0,5 vCPU, 1.000 req/s | 0,83 / 18,19 / 52,93 | Cumpre |
| Pool e log, 0,5 vCPU, 1.200 req/s | 11,67 / 83,63 / 117,86 | Não cumpre (p50 e p95) |

  [FATO: `tests/load/results/2026-10-12-local-baseline.csv`, medianas calculadas neste turno]
- O Fargate não aceita 0,5 vCPU com 512 MB: com 512 de CPU a memória válida vai de 1024 a 4096 MiB. [FATO: validação em [`modules/ecs/variables.tf`](../../infrastructure/modules/ecs/variables.tf) linhas 60-72]
- A arquitetura ARM64 é o padrão do módulo e a imagem é publicada como `linux/amd64,linux/arm64`. [FATO: [`modules/ecs/variables.tf`](../../infrastructure/modules/ecs/variables.tf) linhas 32-41 e [`deploy.yml`](../../.github/workflows/deploy.yml) linha 85]
- O `dev` usa `task_cpu = 512` e `task_memory = 1024`. [FATO: [`dev.tfvars`](../../infrastructure/environments/dev.tfvars) linhas 63-64]
- Preços Fargate em us-east-1: ARM64 a US$ 0,03238 por vCPU-hora e US$ 0,00356 por GB-hora; x86 a US$ 0,04048 e US$ 0,004446. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Preços de referência", fonte aws.amazon.com/fargate/pricing]
- Não se sabe se o Fargate aplica a cota de CPU com throttling igual ao cgroup local. [FATO: lista "DESCONHECIDO" em [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md)]

## Decisão

Usar Fargate ARM64 com 0,5 vCPU e 1 GB por task. O tamanho vem do benchmark LOCAL e deve ser revalidado na AWS antes de ser tratado como capacidade.

## Alternativas consideradas

Custos calculados com a tabela de preços da steering e 730 horas por mês (convenção de cálculo, não preço da AWS):

| Alternativa | Cálculo por hora | Por mês (730 h) | Motivo |
|---|---|---|---|
| ARM64, 0,5 vCPU e 1 GB (escolhida) | 0,5 × 0,03238 + 1 × 0,00356 = US$ 0,01975 | US$ 14,42 | Cumpre o SLO local até 1.000 req/s |
| x86, 0,5 vCPU e 1 GB | 0,5 × 0,04048 + 1 × 0,004446 = US$ 0,024686 | US$ 18,02 | Mais cara que ARM64 para o mesmo tamanho |
| ARM64, 0,25 vCPU e 0,5 GB | 0,25 × 0,03238 + 0,5 × 0,00356 = US$ 0,009875 | US$ 7,21 | Não cumpriu o SLO de `/connect` em nenhuma taxa da série principal (cota em todas as threads). O controle com cota só na thread principal ficou dentro do SLO a 400 req/s; ver [benchmark-local](../performance/benchmark-local.md#nuances-que-a-steering-não-destaca). O benchmark variou só a CPU; memória não foi variável medida |
| ARM64, 0,25 vCPU e 1 GB | 0,25 × 0,03238 + 1 × 0,00356 = US$ 0,011655 | US$ 8,51 | Mesmo limite de CPU da anterior |

## Consequências

- A task custa cerca de US$ 7 por mês a mais que a de 0,25 vCPU. O orçamento total da steering (~US$ 34/mês em 24x7) já considera a task de 0,5 vCPU. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Orçamento e estimativas"]
- Todos os números de latência e taxa são LOCAIS, em CPU x86 e com Postgres local sem TLS. A estimativa para a AWS divide a taxa local por 2 e **não foi medida**. [FATO: [`08-testes-de-carga.md`](../../.kiro/steering/08-testes-de-carga.md) seção "Estimativas atuais"]
- O autoscaling (min 1, max 3) escala por CPU média em 60%. Ver [`docs/autoscaling.md`](../autoscaling.md).
- O benchmark local não foi repetido com a imagem final (`--cpus=0.5` e `DB_POOL_MAX=3`). O baseline usou pool de 5; a AWS usa 3. [FATO: [`08-testes-de-carga.md`](../../.kiro/steering/08-testes-de-carga.md) regra de execução 6]
- O build `linux/arm64` não foi executado na máquina local, que não tem QEMU. O CI declara o build arm64 sem push. [FATO: [`ci.yml`](../../.github/workflows/ci.yml) linhas 94-119]

## Status

Aceito. Decisão travada em [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md). Implementada no código, não validada na AWS.
