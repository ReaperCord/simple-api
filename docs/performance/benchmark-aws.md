# Benchmark na AWS (pelo API Gateway): 13/10/2026

**Rótulo: AWS.** Não misturar com o `benchmark-local.md` (LOCAL).

## Condições

| Item | Valor |
|---|---|
| Gerador | PC do Leandro (Brasil), k6 v2.2.0, fora da AWS |
| Alvo | HTTP API `$default` → VPC Link V2 → Cloud Map SRV → ECS Fargate |
| Imagem | `simple-api@sha256:b78f973d…` (task definition `simple-api-dev:2`) |
| Task | 0,5 vCPU / 1 GB, ARM64, 1 réplica, autoscaling ativo (não disparou) |
| RDS | `db.t4g.micro`, PostgreSQL 16.13, `max_connections = 79` (medido) |
| Throttling do estágio | 50 req/s, burst 100 (`dev.tfvars`) |
| Script | `tests/load/aws/load.js` (`constant-arrival-rate`) |
| Dados | `tests/load/results/2026-10-13-aws-apigw.csv` e `…-backend.txt` |

Desvio da steering (`08-testes-de-carga.md`): baseline a **40 req/s** em vez de 50, para ficar abaixo do throttling de 50 req/s e não medir `429`. Aquecimento de 10 s descartado em cada série; 3 séries, cada uma sem reiniciar a task (a regra pede task nova por série: **não cumprido**).

## Resultado (cliente → API Gateway, inclui ~110–130 ms de rede Brasil ↔ us-east-1)

| Série | Taxa / duração | Requisições | p50 | p95 | p99 | Erros | CPU do gerador (média / pico) |
|---|---|---|---|---|---|---|---|
| smoke (`/` e `/connect`) | 5 req/s / 60 s | 301 | 154 ms | 199 ms | 210 ms | 0 | 20% / 50% |
| baseline 1 (`/connect`) | 40 req/s / 300 s | 12.000 | 134 ms | 153 ms | 183 ms | 0,008% (1 falha, max 5 s) | 18% / 63% |
| baseline 2 | idem | 12.001 | 132 ms | 154 ms | 186 ms | 0,008% (1 resposta 5xx) | 18% / **83%** |
| baseline 3 | idem | 12.001 | 134 ms | 165 ms | 210 ms | 0 | 24% / 80% |

Sem `429` e sem `dropped_iterations` em nenhuma série. O pico de CPU do gerador na série 2 passou de 80% em uma amostra de 5 s (a média ficou em 18%); a regra pede < 80%, então a série 2 tem essa ressalva.

## Latência da aplicação (dentro da task, `/connect`, status 200)

p50 **0,96 ms**, p95 **1,12 ms**, p99 **5,8 ms**, máximo 309 ms (n = 34.973). Contagem não reconciliada com as ~37.350 requisições enviadas (ver `…-backend.txt`).

## Parte B: dentro da VPC, direto na task da API (sem API Gateway), `/connect`

**Rótulo: AWS.** Gerador: task Fargate x86 2 vCPU / 4 GB com `grafana/k6:2.2.0` (CPU média 4–10%, pico máximo 22%, lida de `/proc/stat`), mesma VPC; alvo = IP da task (Cloud Map). 1 task da API (0,5 vCPU / 1 GB ARM64), **autoscaling suspenso**. Script: `tests/load/aws-vpc/incluster.js`. Dados: `tests/load/results/2026-10-13-aws-vpc.csv` e `…-aws-vpc-raw.txt`. Latências medidas pelo k6 dentro da VPC (sem a rede do Brasil).

| Perfil | Taxa | Requisições | p50 | p95 | p99 | max | Erro | Descartadas |
|---|---|---|---|---|---|---|---|---|
| load | 125 req/s (3 min) | 22.501 | 1,35 ms | 1,72 ms | 5,3 ms | 267 ms | 0 | 0 |
| load | 250 | 45.000 | 1,19 ms | 1,52 ms | 4,5 ms | 115 ms | 0 | 0 |
| load | 375 | 67.492 | 1,10 ms | 1,46 ms | 6,2 ms | 315 ms | 0 | 9 |
| load | 500 | 90.001 | 1,06 ms | 1,41 ms | 6,8 ms | 161 ms | 0 | 0 |
| stress | 500 (2 min) | 59.983 | 0,97 ms | 1,19 ms | 5,8 ms | 251 ms | 0 | 18 |
| stress | 625 | 74.986 | 0,95 ms | 1,24 ms | 8,0 ms | 202 ms | 0 | 15 |
| stress | 750 | 89.979 | 0,94 ms | 1,26 ms | 7,1 ms | 189 ms | 0 | 22 |
| stress | 875 | 104.937 | 0,93 ms | 1,26 ms | 13,2 ms | 225 ms | 0 | 64 |
| stress | 1.000 | 119.932 | 0,94 ms | 1,40 ms | 7,9 ms | 189 ms | 0 | 69 |
| breakpoint | rampa 100 → 1.500 em 10 min | 479.628 | 1,06 ms | 1,95 ms | 54 ms | 498 ms | 0 | 367 |

CPU da API (`AWS/ECS CPUUtilization`, média por minuto, **por perfil, não por degrau**): load 32%; stress até 63% (pico 65%); breakpoint até 81% (pico 85%).

Leitura:
- Todos os degraus passam no SLO de `/connect` (p50 ≤ 5, p95 ≤ 50, p99 ≤ 150 ms, erro < 0,1%).
- **Breakpoint não encontrado:** a rampa chegou a 1.500 req/s sem erro e com p99 total de 54 ms; o critério de aborto (erro > 1% ou p99 > 1 s) nunca disparou. O teto real está acima de 1.500 req/s, com a CPU da task em 81–85%.
- Capacidade garantida pela fórmula da steering (maior taxa aprovada no `load` ÷ 1,5): 500 ÷ 1,5 ≈ **333 req/s**, mas o `load` parou em 500 (a estimativa); o `stress` sustentou 1.000 req/s sem erro. A estimativa de 500 req/s da steering era conservadora.
- Inferência (não medida): a 1.000 req/s a CPU média da task ficou em ~63%, perto do alvo de 60% do target tracking, então o autoscaling provavelmente adicionaria task por volta de ~1.000 req/s por task. Reação e tempo de subida da task nova seguem **não medidos** (autoscaling estava suspenso).

Limites desta parte: 1 série por perfil (a regra pede 3; cada série não usou task nova da API); CPU da API só com granularidade de 1 min; throttling de CPU do Fargate não medido; `dropped_iterations` pequenos (até 69 de ~120 mil) sem como separar limite do gerador de limite da API.

## O que isto NÃO mostra

- Não valida o SLO "via API GW, cliente em us-east-1" (p50 ≤ 25 ms): o cliente está no Brasil. A latência da app (≈ 1 ms) e a da rede (~130 ms) estão separadas acima.
- Pela parte A, capacidade e autoscaling: ficaram de fora (limite de 50 req/s do throttling); a parte B acima cobre capacidade dentro da VPC. A reação do autoscaling continua **estimada** (`docs/autoscaling.md`).
- Se o Cloud Map cobra por `DiscoverInstances`: a verificar no Cost Explorer (dados de custo só no dia seguinte).
