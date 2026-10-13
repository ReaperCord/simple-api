# Itens 1 e 2: spike com autoscaling real e restore PITR real

Data: 13/10/2026. Status: item 1 (spike e autoscaling) **executado em 13/10/2026** com OK do Leandro: resultados em `docs/performance/benchmark-aws.md` (parte C), throttling restaurado em 50/100, SG do gerador removido e task definition desregistrada. Item 2 (restore PITR) **executado**: restore aceito pelo Free plan, `available` em 15,4 min, marcador verificado, instância restaurada apagada; ver `docs/dr.md`.

## 1. Spike pelo API Gateway com autoscaling ligado

Gerador: task Fargate efêmera `grafana/k6:2.2.0` (2 vCPU / 4 GB), na VPC, chamando a **URL pública do API Gateway** (cliente em us-east-1: fecha também o SLO "via API GW, cliente em us-east-1" que ficou aberto na parte A). Não precisa de regra no SG do ECS.

| Fase | Taxa | Duração |
|---|---|---|
| base | 100 req/s | 60 s |
| spike | salto para 1.500 req/s em 10 s e mantém | 10 min |
| cauda | volta a 100 req/s | 20 min (observar o scale-in) |

1.500 req/s em 1 task dá ~81% de CPU (medido na parte B), então passa do alvo de 60%.

Mudança fora do Terraform: **elevar o throttling do estágio `$default`** de 50/100 para 3.000/5.000 (dentro do limite da conta, 10.000 req/s e burst 5.000) e **restaurar 50/100 no fim**.

Medições (amostragem a cada ~10 s): `runningCount`/`desiredCount` do service, instâncias no Cloud Map, estado dos alarmes `TargetTracking-*`, `describe-scaling-activities`, CPU média por minuto (`AWS/ECS`), latência e erros do k6 por fase. Resultado: linha do tempo (início do spike → alarme em ALARM → task nova RUNNING → saudável e registrada → CPU/latência estabilizam → scale-in).

Esperado pela doc dos alarmes (verificado em `describe-alarms`): scale-out = 3 períodos de 1 min > 60%; scale-in = 15 períodos de 1 min < 54%.

### FinOps (5 itens)
1. **O que muda:** SG do gerador (temporário, `Track=loadtest`), task definition do gerador, task efêmera, estágio com throttling alterado (revertido). O autoscaling escala o service de 1 até 3 tasks.
2. **Custo:** requisições no API Gateway ≈ 1,03 milhão × US$ 1/milhão = **US$ 1,03** (até US$ 2,06 se o Cloud Map cobrar `DiscoverInstances` por requisição, ainda DESCONHECIDO); gerador 2 vCPU ≈ US$ 0,099/h × ~0,6 h ≈ US$ 0,06; até 2 tasks extras ≈ 2 × (US$ 0,0198 + US$ 0,005)/h × ~0,5 h ≈ US$ 0,025; stack ligada mais ~1 h ≈ US$ 0,04. **Total ≤ ~US$ 2,3.** Preços da tabela de `02-finops-guardrails.md`.
3. **Depois do destroy:** nada deve ficar (SG e task definition removidos).
4. **Tempo:** ~35 min de execução, mais preparo.
5. **Free plan:** Fargate e API Gateway já funcionam na conta. A verificar: se o plano aceita escalar para 3 tasks (RDS tem 79 conexões; 3 tasks × pool 3 = 9).

Riscos: RDS T4g pode cobrar crédito de CPU (baixo: `SELECT version()` é leve); se o estágio ficar com throttling alto esquecido, perde-se a proteção (reverter é passo obrigatório e verificado).

## 2. Restore PITR real (mede o RTO)

Passos:
1. Gravar uma linha-marcador no banco de origem (tabela `dr_marker`, via task efêmera com a imagem da app, como no `max_connections`).
2. Esperar `LatestRestorableTime` passar do marcador (mede o RPO real).
3. `aws rds restore-db-instance-to-point-in-time` para uma instância nova `simple-api-dev-db-restore` (`db.t4g.micro`, mesmo subnet group e SG do RDS, não pública, tags `Project=simple-api`, `Track=drtest`, `TTL`), cronometrando: pedido → `available`.
4. Conectar com a task efêmera (TLS `verify-full`, senha do segredo da origem) e conferir que o marcador existe.
5. Apagar a instância restaurada (`delete-db-instance --skip-final-snapshot --delete-automated-backups`) e confirmar com o `residual-check.sh`.

Registro: RPO observado (marcador → `LatestRestorableTime`), duração de cada parcela do RTO e o resultado da verificação, em `docs/dr.md`.

### FinOps (5 itens)
1. **O que muda:** 1 instância RDS temporária (restore), 1 tabela de teste no banco de `dev`; ambos descartáveis.
2. **Custo:** RDS `db.t4g.micro` ~US$ 0,016/h (APROXIMADO) por ~0,5 a 1 h ≈ US$ 0,01 a 0,02; storage gp3 20 GiB **a verificar** (centavos por hora); task efêmera = segundos. **Total ≲ US$ 0,05.**
3. **Depois do destroy:** a instância restaurada é apagada no próprio teste; o backup automático dela some junto (`--delete-automated-backups`). Confirmar com o `residual-check.sh`.
4. **Tempo:** ~30 a 45 min (o restore do RDS costuma levar vários minutos, a medir).
5. **Free plan:** DESCONHECIDO se aceita restore PITR (a criação com retenção 1 foi aceita). Se recusar, registra-se o erro e o RTO fica "não medido, recusado pelo plano".
