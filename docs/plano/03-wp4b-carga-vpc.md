# WP4 parte B: carga dentro da VPC (load, breakpoint, stress)

Data: 13/10/2026. Status: **executado em 13/10/2026** (OK do Leandro). Resultados em `docs/performance/benchmark-aws.md`; recursos temporários removidos (SG do gerador, regra de ingress, task definition desregistrada, autoscaling reativado).

## Desenho

Gerador: task Fargate efêmera `grafana/k6` (Docker Hub, imagem base `alpine`, entrypoint `k6`; verificado no Dockerfile do repo grafana/k6), x86, 2 vCPU / 4 GB, na subnet pública com IP público (para puxar a imagem), mesma VPC. Alvo: IP da task da API obtido com `aws servicediscovery list-instances` (hoje 1 instância, porta 3000), sem passar pelo API Gateway. Script entra por variável de ambiente em base64 e o entrypoint é trocado para `sh -c`.

| Perfil (1 série cada) | Carga | Duração |
|---|---|---|
| load | degraus 125, 250, 375, 500 req/s (25/50/75/100% da estimativa de 500 req/s para 0,5 vCPU) | 4 × 3 min |
| breakpoint | rampa 100 → 1.500 req/s; aborta com erro > 1% ou p99 > 1 s | até 10 min |
| stress | rampa 500 → 1.000 req/s (100% → 200%), 1 task | 10 min |

Rota `/connect` (a mais pesada). Aquecimento de 10 s descartado. Autoscaling **suspenso** durante os testes. Desvio da steering: 1 série por perfil (a regra pede 3), para caber na janela; fica rotulado.

Medições: k6 (p50/p95/p99/max, erro, `dropped_iterations`); CPU do gerador lida de `/proc/stat` dentro da task (Container Insights está desligado no cluster); CPU da task da API por `AWS/ECS CPUUtilization` (1 min, sem Insights); latência dentro da app pelo log JSON (Logs Insights). Throttling de CPU do Fargate: não medido (precisa do endpoint de metadata; fica como a verificar).

## Mudanças fora do Terraform (todas revertidas no fim)

| # | Mudança | Reversão |
|---|---|---|
| 1 | SG `simple-api-dev-loadgen` (tag Project=simple-api, Track=loadtest) | `delete-security-group` |
| 2 | Regra de ingress na SG do ECS: tcp 3000 a partir do SG do gerador | `revoke-security-group-ingress` (ou some com o destroy) |
| 3 | Autoscaling: suspender scale-in/scale-out do scalable target | reativar (`suspended-state` tudo `false`) |
| 4 | Task definition `simple-api-dev-loadgen` (logs no group `/ecs/simple-api-dev`, prefixo `loadgen`, role de execução existente) | `deregister-task-definition` |
| 5 | Tasks efêmeras `run-task` (param ao fim do teste) | saem sozinhas; conferir `list-tasks` |

Na saída: `tools/residual-check.sh` e conferência de que o autoscaling voltou a `false` e a regra de SG saiu.

## FinOps (5 itens)

1. **O que muda:** itens 1 a 5 acima; nenhum recurso do Terraform é alterado (apenas suspensão do autoscaling).
2. **Custo:** gerador Fargate x86 2 vCPU/4 GB = 2 × US$ 0,04048 + 4 × US$ 0,004446 ≈ **US$ 0,099/h** (tabela de 02-finops); ~45 min ≈ US$ 0,07; IPv4 do gerador US$ 0,005/h; stack ligada mais ~1 h ≈ US$ 0,04. Crédito de CPU do RDS T4g acima do baseline: US$ 0,075/vCPU-h; **teto** se a CPU do RDS ficasse saturada nos 45 min ≈ US$ 0,09 (provavelmente bem menos: `SELECT version()` é leve). **Total ≤ ~US$ 0,25.** Sem requisições no API Gateway (tráfego direto à task). Cloud Map: 3 chamadas de listagem.
3. **Depois do destroy:** nada deve ficar (SG e task definition removidos; task definitions desregistradas não cobram). Confirmar com o `residual-check.sh`.
4. **Tempo:** ~45 min de teste + preparo; fecha dentro da janela (~02h UTC).
5. **Free plan:** Fargate e IP público já funcionam nesta conta. **A verificar:** pull da imagem do Docker Hub (limite anônimo por IP) e se o plano aceita 2 vCPU/4 GB no gerador.

## Riscos

- O RDS é `db.t4g.micro` (T4g Unlimited): carga alta pode gerar cobrança de crédito de CPU (teto acima).
- Se o stress derrubar a task da API, o ECS a recria (circuit breaker ligado); o resultado ainda vale como breakpoint.
- Esquecer a limpeza deixa o SG com tag `Track=loadtest` aparecendo no `residual-check.sh` e atrapalha o destroy da VPC.
