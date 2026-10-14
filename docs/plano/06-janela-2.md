# Janela 2 de AWS: validar o usuário IAM, soak, séries restantes e RTO do DR

Data do desenho: 14/10/2026. Status: **desenho, aguardando OK do Leandro** (apply, destroy e recursos fora do Terraform).

## O que a janela mede

| # | Objetivo | Como |
|---|---|---|
| 1 | Usuário `app_connect` (só CONNECT) via IAM funciona na AWS | publicar a imagem nova, apply com `db_iam_auth = true`, `tools/run-db-init.sh`, `/connect` = 200, deploy.yml verde; conferir privilégios (`DBINIT ok`), que a task role não lê o segredo e que `app_connect` não cria tabela |
| 2 | Risco de memória da autenticação IAM no `db.t4g.micro` (ADR 0013) | `FreeableMemory` do RDS (CloudWatch) antes e depois do primeiro `/connect` e durante o soak |
| 3 | Séries 2 e 3 dos perfis load, breakpoint e stress dentro da VPC | mesmo gerador k6 da parte B, **task da API nova em cada série** (`stop-task`; o ECS recria), autoscaling suspenso e reativado no fim |
| 4 | Soak de 2 h dentro da VPC | 600 req/s (~60% dos 1.000 req/s que o stress sustentou sem erro; CPU esperada ~40%) em `/connect`, autoscaling suspenso; p50/p95/p99, erro, CPU, `FreeableMemory` |
| 5 | RTO do DR com as parcelas medidas | restore PITR para instância nova (já medido em 16,4 min; repetir com a configuração IAM) + **troca do endpoint na app** (nova revisão da task definition com `DB_HOST` novo e `update-service`) + **ajuste da policy `rds-db:connect`** (o `DbiResourceId` muda); registrar o tempo de cada parcela |

Fora desta janela: trilha EKS (janela própria).

## Sequência

0. `deploy.yml` com `only_build=true` publica a imagem do commit atual (a imagem do ECR não tem o código novo).
1. `infra.yml apply` (54 recursos). Você aprova o gate `infra`.
2. `tools/run-db-init.sh dev` (uma vez) e as verificações do item 1.
3. `deploy.yml` (fluxo normal) com smoke.
4. Séries 2 e 3 de load/breakpoint/stress (~35 min cada conjunto; gerador temporário e regra de SG, como na parte B).
5. Soak de 2 h.
6. Teste de RTO (item 5).
7. Documentar, reverter tudo que foi fora do Terraform, `infra.yml destroy` (gate) e `tools/residual-check.sh`.

Duração: ~5 a 6 h no relógio (a maior parte é espera). Se o item 1 ou 2 falhar de forma que a autenticação IAM não caiba no `db.t4g.micro`, a janela para: o plano é registrar o resultado, destruir e voltar a `db_iam_auth = false` (nova PR e janela), sem insistir nos itens 3 a 5.

## FinOps (5 itens)

1. **O que muda:** a stack de 54 recursos (50 de antes + role, policy, attachment e task definition do `db-init`); fora do Terraform: SG do gerador, regra de ingress na SG do ECS, task definition do gerador, tasks efêmeras, suspensão do autoscaling, instância RDS de restore e uma nova revisão da task definition da API para o teste de troca de endpoint. Tudo revertido ou apagado no fim.
2. **Custo (preços da tabela de `02-finops-guardrails.md`; resultado real da janela 1 em `docs/plano/05-custo-real.md`):**

| Parcela | Cálculo | US$ |
|---|---|---|
| Stack (API + RDS + IPv4), ~5,5 h | ~0,041/h × 5,5 | ~0,23 |
| Gerador k6 x86 2 vCPU/4 GB: séries (~1,2 h) + soak (2 h) | 0,099/h × ~3,3 | ~0,33 |
| Tasks extras e restore RDS (~0,6 h) | ~0,02 | ~0,02 |
| Requisições no API Gateway (deploy, smoke, verificações) | poucas dezenas de milhares | < 0,05 |
| **Estimativa** |  | **~0,65** |
| **Teto** (dobro, para imprevistos como o RDS T4g cobrar crédito de CPU no soak e repetição de séries) |  | **≤ ~1,3** |

   Referência: o dia inteiro de testes da janela 1 custou US$ 1,454 de uso bruto, coberto por crédito (saldo US$ 138,52).
3. **Depois do destroy:** nada deve ficar (SG, task definitions do gerador, instância de restore e a revisão extra da API são removidos ou ficam `INACTIVE`, sem custo). Task definitions `ACTIVE` por `skip_destroy` não cobram. Confirmar com `tools/residual-check.sh`.
4. **Tempo ligado:** ~5 a 6 h.
5. **Free plan:** o que já funcionou na janela 1 (Fargate, API Gateway, Cloud Map, RDS, restore PITR). **Desconhecido:** se o Free plan aceita `iam_database_authentication_enabled` no `db.t4g.micro` (resultado do apply) e o custo de memória.

## Riscos

- Memória do RDS (a doc cita 300 a 1000 MiB extras para IAM; a instância tem 1 GiB): pode derrubar a instância ou degradar. Mitigação: observar `FreeableMemory` desde o primeiro `/connect` e parar se cair demais.
- Soak de 2 h segura a janela aberta; o relógio de custo corre mesmo se a sessão cair (o destroy depende de mim e da sua aprovação do gate).
- Mudanças fora do Terraform: cada uma tem reversão verificada, como na janela 1.
