---
inclusion: fileMatch
fileMatchPattern: ["tests/load/**", "docs/**performance**", "docs/**carga**"]
---

# Testes de carga e honestidade dos números

## Perfis (k6, executores de taxa de chegada)

| Perfil | Carga | Duração | Onde roda |
|---|---|---|---|
| smoke | 5 req/s | 1 min | API Gateway (no pipeline) |
| baseline | 50 req/s | 5 min | API Gateway e dentro da VPC |
| load | degraus de 25% até 100% da capacidade estimada | 3 min/degrau | dentro da VPC; uma série final pelo API Gateway, abaixo do throttling |
| stress | 100% → 200%, 1 task, autoscaling OFF | 10 min | dentro da VPC |
| breakpoint | rampa até erro > 1% ou p99 > 1 s | até quebrar | dentro da VPC |
| spike | 10% → 300% em 10 s, mantém 10 min | 12 min | API Gateway, com o throttling do estágio elevado temporariamente acima do pico |
| soak | 60% | 2 h | dentro da VPC |

Use `constant-arrival-rate` / `ramping-arrival-rate`, nunca VUs fixos para medir capacidade. Sempre `summaryTrendStats: ['p(50)','p(95)','p(99)','max']` e reporte `dropped_iterations`.

Dentro da VPC: o registro do Cloud Map é SRV e o k6 não resolve SRV. O gerador busca os IPs das tasks com `aws servicediscovery discover-instances` antes de cada série (com autoscaling desligado a lista não muda) e distribui as requisições entre eles. O spike precisa do autoscaling, por isso passa pelo API Gateway.

Spike: conte com 3–5 min até a task nova atender (alarme de target tracking + start da task); meça o SLO separadamente nesse intervalo e depois dele.

## SLOs de aceite

| Rota | p50 | p95 | p99 | Erros |
|---|---|---|---|---|
| `/` backend (dentro da VPC) | ≤ 5 ms | ≤ 25 ms | ≤ 100 ms | < 0,1% |
| `/connect` backend | ≤ 5 ms | ≤ 50 ms | ≤ 150 ms | < 0,1% |
| via API GW, cliente em us-east-1 | ≤ 25 ms | ≤ 75 ms | ≤ 200 ms | < 0,1% |

Capacidade garantida = maior taxa aprovada no perfil `load` ÷ 1,5.

## Estimativas atuais (a validar na AWS)

| Cenário | Taxa sustentada | p50 | p95 | p99 |
|---|---|---|---|---|
| 1 task 0,25 vCPU, `/connect`, dentro da VPC | 200 req/s | ≤ 3 ms | ≤ 80 ms | ≤ 300 ms (não cumpre o SLO) |
| 1 task 0,5 vCPU, `/connect`, dentro da VPC | 500 req/s | ≤ 3 ms | ≤ 20 ms | ≤ 100 ms |
| 3 tasks 0,5 vCPU, via API GW | 1.500 req/s (throttling do estágio em 1.000) | ≤ 20 ms | ≤ 50 ms | ≤ 150 ms |

Base: benchmark LOCAL de 12/10/2026 (`tests/load/results/2026-10-12-local-baseline.csv`), com a taxa dividida por 2.

## Regras de execução

1. Aquecimento de 10 s descartado; três séries por perfil, cada uma com processo/task nova; publicar mediana e pior caso.
2. Gerador em máquina diferente da API, com CPU < 80% (medir); senão o teste é inválido.
3. Dentro da VPC, o SG do gerador entra temporariamente como origem na porta 3000 das tasks; remover ao final.
4. Medir CPU throttling: Fargate → `cpu_stats.throttling_data` das estatísticas da task (endpoint de metadata v4; confirmar que vem preenchido); EKS → `container_cpu_cfs_throttled_periods_total`.
5. Depois do primeiro teste pelo API GW, conferir no Cost Explorer se apareceu cobrança de Cloud Map proporcional às requisições.
6. Para reproduzir o baseline local sem root nem cgroup v1, rode a API num container com `docker run --cpus=0.25` (ou `0.5`). Use `DB_POOL_MAX=3`, o valor da AWS (o baseline de 12/10 usou 5).

## Regras de honestidade

1. Nenhum número de latência/RPS no README sem o arquivo correspondente em `tests/load/results/`.
2. Sempre informar: onde rodou o gerador, CPU do gerador, SHA da imagem, tamanho da task, réplicas, data.
3. Separar latência de rede (cliente no Brasil ↔ us-east-1, ~110–130 ms) de latência da aplicação.
4. Números do benchmark local são LOCAIS. Rotular assim. A variação entre rodadas locais chegou a ~65% (11/10 × 12/10).
5. Se o resultado contradiz a estimativa, publicar o resultado e explicar — nunca ajustar o teste para bater a estimativa.
