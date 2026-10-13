# Baseline LOCAL de desempenho — 12/10/2026

**Estes números são de uma VM local. Não são capacidade da AWS.** Servem para comparar versões do código e tamanhos de CPU entre si e para dar a primeira estimativa, que depois é validada na AWS.

## Como foi medido

- VM com 2 vCPUs (Intel Xeon 2,8 GHz), Node 22, Postgres 16 local com autenticação SCRAM e `max_connections=100`.
- API presa ao núcleo 0 e limitada por cgroup v1 (`cpu.cfs_quota_us` 25000 ou 50000 em período de 100000 → 0,25 ou 0,5 vCPU), com o PID escrito em `cgroup.procs` para limitar TODAS as threads do Node. (Escrever em `tasks` move só a thread principal: foi assim na primeira versão da rodada, guardada em `2026-10-12-local-mainthread-only.csv`; o controle mudou pouco os números.)
- k6 0.57 sozinho no núcleo 1 (máximo de 47% de CPU nas rodadas válidas); Postgres no núcleo 0. Um teste de sensibilidade com o Postgres no núcleo 1 deu resultado parecido (`2026-10-12-local-sensitivity-pg-core1.csv`).
- Executor `constant-arrival-rate`, timeout de 5 s, 10 s de aquecimento descartados, degraus de 15 s, 3 séries por configuração com processo novo.
- Variantes: `orig` (código do repo, conexão por requisição), `fixed` (pool de 5 + log JSON por requisição + request id) e `nolog` (pool sem o log por requisição).
- SLO de `/connect` usado na avaliação: p50 ≤ 5 ms, p95 ≤ 50 ms, p99 ≤ 150 ms, erros < 0,1%, taxa atingida ≥ 98% da oferecida (medianas das 3 séries).

## Arquivos

- `load.js` — script k6 usado.
- `bench.sh` — driver (cgroup, aquecimento, séries, coleta de throttling e CPU do gerador).
- `../results/2026-10-12-local-baseline.csv` — séries com todas as threads limitadas (original, pool 0,25 e pool 0,5 vCPU).
- `../results/2026-10-12-local-mainthread-only.csv` — primeira versão (cota só na thread principal), incluindo as variantes `nolog` e a rota `/`.
- Colunas: variante, rota, vCPU, série, taxa oferecida, RPS atingido, % de sucesso, p50, p95, p99, máximo (ms), iterações descartadas, % de períodos com throttling, % de CPU do k6.

## Resumo (mediana de 3 séries)

| Configuração | Melhor ponto (p50 / p95 / p99) | Cumpre o SLO? | Teto |
|---|---|---|---|
| `/connect` original, 0,25 vCPU | 25 req/s: 12 / 23 / 62 ms | Não (p50 > 5 ms) | ~70 req/s ("too many clients" + timeouts) |
| `/connect` pool + log, 0,25 vCPU | 400 req/s: 0,7 / 57 / 130 ms | Não (a 200 req/s o p99 estoura; a 400, o p95) | ~600 req/s |
| `/connect` pool + log, 0,5 vCPU | 1.000 req/s: 0,8 / 18 / 53 ms | Sim, até 1.000 req/s | ~1.300 req/s |
| `/connect` pool sem log, 0,25 vCPU (só thread principal) | 600 req/s: 2,5 / 81 / 139 ms | Não | ~700 req/s |
| `/` com log, 0,25 vCPU (só thread principal) | 600 req/s: 0,5 / 13 / 30 ms | Sim (SLO de `/`) | ~950 req/s |

Uma rodada anterior (11/10, outro host, sem aquecimento nem log; saída bruta em `../results/2026-10-11-local-first-run.txt`) chegou a ~1.000 req/s com 0,25 vCPU, ~65% acima: a variação entre rodadas locais é grande, por isso a estimativa para a AWS divide a taxa medida por 2.

## Limitações conhecidas

- Os logs da app vão para `/dev/null`: o custo do log por requisição medido aqui é um limite inferior.
- O driver usa cgroup v1 e root. Para reproduzir sem isso, rode a API num container com `docker run --cpus=0.25` (ou `0.5`) e o k6 fora dele.
- Postgres local, sem TLS e sem rede entre AZs; CPU x86, não Graviton.
