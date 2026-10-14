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

## Parte C: spike pelo API Gateway com autoscaling ligado (cliente em us-east-1)

**Rótulo: AWS.** Gerador: task Fargate x86 2 vCPU / 4 GB com `grafana/k6:2.2.0` na mesma região (CPU média 7,8%, pico 28%, lida de `/proc/stat`), chamando a URL pública do API Gateway (`/connect`). Autoscaling **ligado** (min 1, max 3, alvo 60%). O throttling do estágio ficou em 3.000/5.000 durante o teste e foi restaurado para 50/100 (verificado). Script: `tests/load/aws-spike/spike.js`. Dados: `tests/load/results/2026-10-13-aws-spike.csv` (por minuto), `…-aws-spike-raw.json` e `…-aws-spike-monitor.csv` (tasks, Cloud Map e alarmes a cada ~5 s).

Perfil: 100 req/s por 60 s, salto para 1.500 req/s em 10 s mantido por 10 min, depois 100 req/s por 20 min. Total: 1.040.473 requisições; 418 respostas 5xx (0,040%); 0 respostas 429; 1.526 iterações descartadas.

Linha do tempo (UTC; o início do salto, ~22:50:05, é estimado pelo primeiro log do k6, com ±5 s):

| Hora | Evento | Fonte |
|---|---|---|
| ~22:50:05 | Salto para 1.500 req/s | k6 (estimado) |
| 22:51 a 22:54 | CPU da única task em 95–98% (saturada) | `AWS/ECS CPUUtilization` |
| **22:55:05** | **Scale-out 1 → 2** decidido (`AlarmHigh`), ~5 min depois do salto | `describe-scaling-activities` |
| 22:55:38 | 2ª instância registrada no Cloud Map | monitor |
| **22:55:49** | **2 tasks rodando** (~44 s depois da decisão) | monitor |
| 22:58:05 | Scale-out 2 → 3 decidido (~3 min depois do primeiro) | `describe-scaling-activities` |
| 22:58:47 | 3 tasks rodando e 3 instâncias no Cloud Map | monitor |
| 22:59 a 23:00 | CPU média cai para 42% e 22% | `AWS/ECS` |
| ~23:00:15 | Fim do spike (volta a 100 req/s) | k6 (estimado) |
| **23:16:07** | **Scale-in 3 → 2** (`AlarmLow`, 15 períodos de 1 min abaixo de 54%) | `describe-scaling-activities` |
| **23:22:07** | **Scale-in 2 → 1** (6 min depois, cooldown de 300 s) | `describe-scaling-activities` |

Latência e erros via API Gateway (cliente em us-east-1), por minuto (completo no CSV):

| Janela (UTC) | O que acontecia | p50 | p95 | p99 | Erro |
|---|---|---|---|---|---|
| 22:49 | base, 100 req/s | 5,2 ms | 9,3 ms | 56 ms | 0 |
| 22:50 a 22:52 | 1.500 req/s, 1 task saturando | 4,9–5,0 ms | 23–33 ms | 60–85 ms | 0,03–0,06% |
| **22:53** | **1 task saturada** | 5,5 ms | **290 ms** | **321 ms** | **0,17%** |
| 22:55 a 22:56 | scale-out em curso | 4,7–4,9 ms | 6,3–32 ms | 16–184 ms | 0,00–0,07% |
| 22:59 | 3ª task entrando | 4,7 ms | 13 ms | **757 ms** | 0 |
| 23:01 a 23:20 | cauda, 100 req/s | 5,7–6,0 ms | 7,6–7,9 ms | 12–15 ms | 0 (exceto 23:16) |
| **23:16** | **scale-in 3 → 2** | 5,8 ms | 7,7 ms | 12,5 ms | 0,15% (8 respostas 5xx) |

SLO "via API GW, cliente em us-east-1" (p50 ≤ 25, p95 ≤ 75, p99 ≤ 200 ms, erro < 0,1%): o **p50 passou em todos os minutos**; o p95 estourou só em 22:53; o p99 estourou em 22:53 e 22:59; o erro passou de 0,1% em 22:53 (0,17%), 23:00 (0,11%) e 23:16 (0,15%). A 100 req/s o SLO é cumprido com folga (p99 12–15 ms).

Leitura:
- Uma única task a 1.500 req/s satura (CPU 95–98%) por ~4–5 min, até o scale-out, mas mantém p50 de ~5 ms; o estrago é no p95/p99 e em 0,03–0,17% de erro por minuto.
- O scale-out leva **~5 min do salto à decisão** e **~44 s** da decisão até a task nova rodando; o segundo degrau ocorre ~3 min depois. O scale-in completo (3 → 1) leva **~22 min depois do fim do spike**.
- O scale-in 3 → 2 gerou 8 respostas 5xx num minuto (indício de requisições para a task que sai; **causa não verificada**).
- A coincidência do p99 de 757 ms (22:59) com a entrada da 3ª task é uma hipótese, não verificada.

Limites: uma única execução; início do salto estimado (±5 s); CPU só com granularidade de 1 min; o monitor amostra a cada ~5 s. Custo real (Cost Explorer, `docs/plano/05-custo-real.md`): o dia inteiro somou 1.078.187 requisições no API Gateway = US$ 1,078 (todas as partes, não só o spike) e US$ 0,073 de Cloud Map (72.921 chamadas).

## O que isto NÃO mostra

- Não valida o SLO "via API GW, cliente em us-east-1" (p50 ≤ 25 ms): o cliente está no Brasil. A latência da app (≈ 1 ms) e a da rede (~130 ms) estão separadas acima.
- Pela parte A, capacidade e autoscaling: ficaram de fora (limite de 50 req/s do throttling); a parte B acima cobre capacidade dentro da VPC. A reação do autoscaling foi medida na parte C (acima).
- (Resolvido) Cloud Map: 72.921 chamadas de API (US$ 0,073) para 1.078.187 requisições, ~1 por 15; ver `docs/plano/05-custo-real.md`.
