# Benchmark LOCAL

**Todos os números deste documento são LOCAIS. Não são capacidade da AWS.** Eles vêm de uma VM local, com CPU limitada por cgroup, e servem para comparar versões do código e tamanhos de CPU entre si. Nenhum teste foi executado na AWS e nenhum benchmark foi rodado para escrever este documento: ele só resume os arquivos que já existem em [`tests/load/results/`](../../tests/load/results).

Rótulos: `[FATO: fonte]` foi lido ou calculado a partir dos arquivos citados, `[HIPÓTESE]` é inferência.

## Arquivos de origem

| Arquivo | Conteúdo |
|---|---|
| [`2026-10-12-local-baseline.csv`](../../tests/load/results/2026-10-12-local-baseline.csv) | Série principal: cota de CPU aplicada a todas as threads do Node. Variantes `orig` (código base, conexão por requisição) e `fixed` (pool e log JSON por requisição), rota `/connect`, 0,25 e 0,5 vCPU. 3 séries por taxa |
| [`2026-10-12-local-mainthread-only.csv`](../../tests/load/results/2026-10-12-local-mainthread-only.csv) | Primeira versão da rodada: cota só na thread principal. Inclui a variante `nolog` e a rota `/`. 3 séries por taxa |
| [`2026-10-12-local-sensitivity-pg-core1.csv`](../../tests/load/results/2026-10-12-local-sensitivity-pg-core1.csv) | Teste de sensibilidade com o Postgres no núcleo 1. **1 série** por taxa, só `nolog` em `/connect` a 0,25 vCPU |
| [`2026-10-11-local-first-run.txt`](../../tests/load/results/2026-10-11-local-first-run.txt) | Primeira rodada (11/10), outro host, sem aquecimento, 1 série por taxa. Guardada só para rastreabilidade |
| [`local-baseline/README.md`](../../tests/load/local-baseline/README.md), [`bench.sh`](../../tests/load/local-baseline/bench.sh), [`load.js`](../../tests/load/local-baseline/load.js) | Método, driver e script k6 |

## Como foi medido

[FATO: [`tests/load/local-baseline/README.md`](../../tests/load/local-baseline/README.md) e [`load.js`](../../tests/load/local-baseline/load.js)]

- VM de 2 vCPUs (Intel Xeon 2,8 GHz), Node 22, Postgres 16 local com SCRAM e `max_connections=100`. A imagem de produção usa Node 24 e CPU ARM64 (Graviton) na AWS. O benchmark usou CPU x86.
- API presa ao núcleo 0 e limitada por cgroup v1: `cpu.cfs_quota_us` de 25000 ou 50000 em período de 100000, equivalente a 0,25 ou 0,5 vCPU.
- k6 0.57 sozinho no núcleo 1, com no máximo 47% de CPU nas rodadas da série principal (confirmado nos CSV, coluna `k6_cpu_pct`). A regra da steering é manter o gerador abaixo de 80%.
- Executor `constant-arrival-rate`, timeout de 5 s por requisição, 10 s de aquecimento descartados, degraus de 15 s, 3 séries por configuração, cada uma com processo novo da API.
- A variante `fixed` usa pool de 5 conexões. A AWS usa `DB_POOL_MAX=3`. O baseline não foi repetido com 3.
- Os logs da aplicação vão para `/dev/null`, então o custo do log por requisição medido aqui é um limite inferior.
- Postgres local, sem TLS e sem rede entre AZs.
- SLO de `/connect` usado: p50 ≤ 5 ms, p95 ≤ 50 ms, p99 ≤ 150 ms, erros abaixo de 0,1% e taxa atingida de pelo menos 98% da oferecida, sempre nas medianas das 3 séries.

## Resultados da série principal

Medianas das 3 séries, calculadas neste turno a partir de [`2026-10-12-local-baseline.csv`](../../tests/load/results/2026-10-12-local-baseline.csv). Latências em ms. `thr` é a mediana da porcentagem de períodos de 100 ms com throttling de CPU.

### `/connect`, variante `fixed` (pool e log), LOCAL

| vCPU | Taxa oferecida (req/s) | Taxa atingida (req/s) | p50 | p95 | p99 | Descartadas | thr (%) | Cumpre o SLO? |
|---|---|---|---|---|---|---|---|---|
| 0,25 | 200 | 200 | 1,06 | 37,81 | 186,43 | 0 | 19 | Não (p99) |
| 0,25 | 400 | 400 | 0,68 | 56,69 | 129,78 | 0 | 32 | Não (p95) |
| 0,25 | 600 | 599 | 25,02 | 148,41 | 185,62 | 0 | 98 | Não |
| 0,25 | 800 | 554 | 1460,15 | 1895,59 | 2159,91 | 2926 | 99 | Não |
| 0,5 | 400 | 400 | 0,72 | 14,78 | 80,91 | 0 | 6 | Sim |
| 0,5 | 800 | 800 | 0,66 | 6,88 | 28,09 | 0 | 4 | Sim |
| 0,5 | 1000 | 1000 | 0,83 | 18,19 | 52,93 | 0 | 20 | Sim |
| 0,5 | 1200 | 1200 | 11,67 | 83,63 | 117,86 | 0 | 82 | Não (p50 e p95) |
| 0,5 | 1400 | 1288 | 187,88 | 524,77 | 614,31 | 1090 | 97 | Não |

### `/connect`, variante `orig` (código base, conexão por requisição), 0,25 vCPU, LOCAL

| Taxa oferecida (req/s) | Taxa atingida (req/s) | Sucesso (%) | p50 | p95 | p99 | Descartadas | Cumpre o SLO? |
|---|---|---|---|---|---|---|---|
| 25 | 25 | 100 | 11,82 | 22,52 | 61,70 | 0 | Não (p50) |
| 50 | 50 | 100 | 18,69 | 188,53 | 250,52 | 0 | Não |
| 75 | 69 | 100 | 1485,65 | 2135,35 | 2716,54 | 0 | Não |
| 100 | 70 | 74,78 | 2001,20 | 5000,76 | 5001,15 | 106 | Não |

### Controle com a cota só na thread principal, LOCAL

Medianas de [`2026-10-12-local-mainthread-only.csv`](../../tests/load/results/2026-10-12-local-mainthread-only.csv). Latências em ms.

| Variante, rota | vCPU | Oferecida (req/s) | Atingida (req/s) | p50 | p95 | p99 | Descartadas |
|---|---|---|---|---|---|---|---|
| `fixed`, `/connect` | 0,25 | 400 | 400 | 0,81 | 48,30 | 110,67 | 0 |
| `fixed`, `/connect` | 0,25 | 600 | 599 | 37,17 | 153,37 | 186,42 | 0 |
| `fixed`, `/connect` | 0,25 | 800 | 549 | 1501,01 | 2051,12 | 2323,49 | 2987 |
| `fixed`, `/connect` | 0,5 | 1000 | 1000 | 0,85 | 14,21 | 34,09 | 0 |
| `fixed`, `/connect` | 0,5 | 1200 | 1197 | 8,50 | 86,54 | 116,55 | 0 |
| `fixed`, `/connect` | 0,5 | 1400 | 1303 | 195,07 | 441,29 | 522,04 | 929 |
| `nolog`, `/connect` | 0,25 | 400 | 400 | 0,95 | 43,01 | 77,61 | 0 |
| `nolog`, `/connect` | 0,25 | 600 | 600 | 2,53 | 80,99 | 139,21 | 0 |
| `nolog`, `/connect` | 0,25 | 800 | 715 | 530,25 | 868,14 | 901,30 | 773 |
| `fixed`, `/` | 0,25 | 400 | 400 | 0,55 | 7,41 | 28,30 | 0 |
| `fixed`, `/` | 0,25 | 600 | 600 | 0,46 | 13,11 | 30,25 | 0 |
| `fixed`, `/` | 0,25 | 800 | 800 | 9,54 | 57,81 | 80,75 | 0 |
| `fixed`, `/` | 0,25 | 1000 | 932 | 143,50 | 381,71 | 4999,14 | 316 |

### Sensibilidade com o Postgres no núcleo 1 (1 série, não é mediana)

[`2026-10-12-local-sensitivity-pg-core1.csv`](../../tests/load/results/2026-10-12-local-sensitivity-pg-core1.csv), `nolog`, `/connect`, 0,25 vCPU.

| Oferecida (req/s) | Atingida (req/s) | p50 | p95 | p99 | Descartadas |
|---|---|---|---|---|---|
| 600 | 593 | 46,61 | 464,20 | 520,73 | 102 |
| 800 | 766 | 67,87 | 403,06 | 453,51 | 210 |
| 1000 | 706 | 1155,04 | 1708,48 | 1858,86 | 3724 |
| 1200 | 727 | 1216,36 | 1487,02 | 1608,20 | 6314 |

### Primeira rodada de 11/10 (só rastreabilidade)

[FATO: [`2026-10-11-local-first-run.txt`](../../tests/load/results/2026-10-11-local-first-run.txt)] Outro host, sem aquecimento, uma série por taxa, cota só na thread principal e variante `fixed` sem log por requisição. **Não usar como referência de capacidade.** Com SCRAM, `fixed` em 0,25 vCPU sustentou 997 req/s a 1000 oferecidas, e em 0,5 vCPU sustentou 1999 req/s a 2000 oferecidas. Na rodada válida de 12/10, os mesmos pontos de saturação foram cerca de 600 e 1.300 req/s. A diferença entre rodadas locais é grande.

## Conferência da tabela da steering contra os CSV

A tabela de "Medições LOCAIS" de [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) e o resumo de [`local-baseline/README.md`](../../tests/load/local-baseline/README.md) foram conferidos linha a linha. Valores da steering são arredondados.

| Linha da steering (LOCAL) | Steering diz (p50 / p95 / p99) | CSV (mediana) | Confere? |
|---|---|---|---|
| `/connect` original, 0,25 vCPU, 25 req/s | 12 / 23 / 62 | 11,82 / 22,52 / 61,70 (baseline) | Sim |
| Teto da `/connect` original | ~70 req/s | 70 req/s atingidos a 100 oferecidas, com 74,78% de sucesso (baseline) | Sim |
| Pool e log, 0,25 vCPU, 400 req/s | 0,7 / 57 / 130 | 0,68 / 56,69 / 129,78 (baseline) | Sim |
| Mesma linha: "a 200 req/s o p99 estoura; a 400, o p95" | p99 de 186 ms a 200 req/s (texto de [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md)) | p99 = 186,43 a 200 req/s; p95 = 56,69 a 400 req/s (baseline) | Sim |
| Teto de 0,25 vCPU | ~600 req/s | 599 atingidos a 600 oferecidas, mas com p50 de 25 ms; 554 a 800 oferecidas (baseline) | Sim, como teto de vazão. Não cumpre o SLO nesse ponto |
| Pool e log, 0,5 vCPU, 1.000 req/s | 0,8 / 18 / 53 | 0,83 / 18,19 / 52,93 (baseline) | Sim |
| Teto de 0,5 vCPU | ~1.300 req/s | 1288 atingidos a 1400 oferecidas (baseline) | Sim |
| Pool sem log, 0,25 vCPU, 600 req/s, cota só na thread principal | 2,5 / 81 / 139 | 2,53 / 80,99 / 139,21 (mainthread-only) | Sim |
| Teto da linha `nolog` | ~700 req/s | 715 atingidos a 800 oferecidas (mainthread-only) | Sim |
| `/` com log, 0,25 vCPU, 600 req/s, cota só na thread principal | 0,5 / 13 / 30 | 0,46 / 13,11 / 30,25 (mainthread-only) | Sim |
| Teto de `/` | ~950 req/s | 932 a 1000 oferecidas e 978 a 1200 oferecidas (mainthread-only) | Sim |
| Variação entre rodadas locais | ~65% acima na rodada de 11/10 | 997 contra ~600 req/s, cerca de 66% | Sim |

Nenhum número da tabela principal da steering divergiu dos CSV. As divergências abaixo são de interpretação, não de valor.

## Nuances que a steering não destaca

1. **O controle com a cota só na thread principal não "mudou pouco" em um ponto que importa.** A steering escreve que o controle com todas as threads "mudou pouco". A 0,25 vCPU e 400 req/s, a série principal (todas as threads) dá p95 de 56,69 ms e reprova o SLO, enquanto o controle (só thread principal) dá p95 de 48,30 e p99 de 110,67 e o cumpre. O throttling foi de 32% contra 57%. Em outras taxas as diferenças são menores. Por isso a afirmação de que 0,25 vCPU "não cumpriu o SLO em nenhuma taxa" vale para a série principal, não para o controle. A decisão por 0,5 vCPU continua amparada: nas duas séries o 0,25 vCPU não passa em 200 req/s (p99) e perde a folga de latência perto de 400 req/s. [FATO: comparação dos dois CSV]
2. **A sensibilidade com o Postgres no núcleo 1 só é "parecida" no teto de vazão.** O README do baseline diz que o resultado foi parecido. Os tetos são próximos (766 req/s contra 715 req/s a 800 oferecidas), mas a latência a 600 req/s não é: p50 de 46,61 ms contra 2,53 ms e p95 de 464,20 ms contra 80,99 ms, e o teste tem uma única série. Não há como dizer, com 1 série, se isso é efeito do núcleo do Postgres ou ruído. [FATO: comparação de `sensitivity-pg-core1.csv` com `mainthread-only.csv`; HIPÓTESE sobre a causa]
3. **"Teto" é vazão, não SLO.** O teto de 0,25 vCPU (~600 req/s) e o de 0,5 vCPU (~1.300 req/s) são a taxa máxima atingida antes do colapso. A faixa que cumpre o SLO é menor: até 1.000 req/s com 0,5 vCPU (a 1.200 req/s o p50 mediano é 11,67 ms e o p95 é 83,63 ms) e nenhuma taxa testada com 0,25 vCPU na série principal.
4. **Pool de 5, Node 22, x86 e Postgres sem TLS.** A AWS usa pool de 3, Node 24, ARM64 e TLS `verify-full`. Nenhuma dessas diferenças foi medida. A estimativa da steering para a AWS divide a taxa local por 2 e não tem medição própria. [FATO: [`08-testes-de-carga.md`](../../.kiro/steering/08-testes-de-carga.md) seção "Estimativas atuais"]
5. **Pontos com poucas séries.** A dispersão entre as 3 séries é grande em alguns pontos. Exemplo: 0,5 vCPU a 1.000 req/s, p95 de 18,19 (mediana) com valores de 14,11 a 30,58 nas três séries, e throttling de 18% a 45%. [FATO: linhas `fixed,/connect,0.50,*,1000` do baseline]

## O que não foi feito

- O benchmark não foi repetido com a imagem final (`docker run --cpus=0.5`, `DB_POOL_MAX=3`), como prevê a regra 6 de [`08-testes-de-carga.md`](../../.kiro/steering/08-testes-de-carga.md). A compatibilidade do `load.js` com k6 2.x também não foi conferida (o baseline usou k6 0.57).
- Nenhum teste de carga na AWS: smoke, baseline, load, stress, breakpoint, spike e soak estão só planejados. Ver [`08-testes-de-carga.md`](../../.kiro/steering/08-testes-de-carga.md).
- Não se sabe se o Fargate aplica a cota de CPU com throttling igual ao cgroup local.
- Não há medição de latência de rede entre cliente e `us-east-1` nem pelo API Gateway.
