# Verificação: estado final da janela de 13/10/2026

Papel: `kxc-verificador` (`.kiro/prompts/verificador.md`), executado por Claude no mesmo turno em que os docs foram escritos. **Não é uma auditoria independente**: quem escreveu os docs também os conferiu. A tentativa de reduzir esse viés foi checar números contra os arquivos de dados e o estado vivo (GitHub e AWS), sem reusar o que eu mesmo digitei nos docs.

Escopo: `README.md` (Pendências), `docs/performance/benchmark-aws.md`, `docs/autoscaling.md`, `docs/dr.md`, `docs/plano/*` e `tests/load/results/2026-10-13-*`.

## Afirmações verificadas

| # | Afirmação | Status | Evidência |
|---|---|---|---|
| 1 | Smoke pelo API GW: 301 req, p50 154 / p95 199 / p99 210 ms | ✅ | `2026-10-13-aws-apigw.csv` linha 1 |
| 2 | Baseline 1 a 3 (12.000 / 12.001 / 12.001 req; p50 134/132/134; p95 153/154/165; p99 183/186/210) | ✅ | mesmo CSV |
| 3 | CPU do gerador na série 2 chegou a 83% (> 80%, ressalva documentada) | ✅ | CSV, `cpu_gerador_max_pct` = 83 |
| 4 | Parte B, 9 degraus de load e stress (req, p50, p95, p99, max, erro 0) | ✅ | `2026-10-13-aws-vpc.csv`: 0 divergências |
| 5 | Breakpoint: 479.628 req, erro 0, p99 54 ms, 367 descartadas | ✅ | mesmo CSV |
| 6 | CPU da API por perfil: load 32%, stress 63% (pico 65), breakpoint 81% (pico 85) | ✅ | mesmo CSV (a 1ª checagem automática falhou por erro meu na ordem das taxas; refeita por perfil) |
| 7 | Spike: 1.040.473 req, 418 respostas 5xx (0,040%) | ✅ | `2026-10-13-aws-spike.csv` |
| 8 | Spike m04 (22:53): p95 290, p99 321 ms, erro 0,17%; m10 p99 757 ms; m27 com 8 respostas 5xx | ✅ | mesmo CSV |
| 9 | p50 < 25 ms em todos os minutos; erro > 0,1% só em m04, m11 e m27; p95 > 75 só em m04; p99 > 200 em m04 e m10 | ✅ | mesmo CSV |
| 10 | 2 tasks rodando 22:55:49 e 3 tasks 22:58:47 | ✅ | `2026-10-13-aws-spike-monitor.csv` |
| 11 | Restore PITR: `available` em 924 s (15,4 min), marcador verificado em 986 s (16,4 min), marcador `pre-restore` retornado | ✅ | `2026-10-13-aws-dr-restore-log.txt` |
| 12 | FinOps: Fargate 0,5 vCPU/1 GB = US$ 0,0198/h = US$ 14,42/mês; IPv4 US$ 3,65/mês | ✅ | recálculo com os preços da tabela de `02-finops-guardrails.md` |
| 13 | Apply `infra.yml` (run 38459253681): sucesso, 17 added | ✅ | `gh run view`, log: "Apply complete! Resources: 17 added, 0 changed, 1 destroyed" |
| 14 | `deploy.yml` de ponta a ponta (run 38461659742) | ✅ | `gh run view`: success |
| 15 | Destroy (run 38486943440): 50 destroyed | ✅ | `gh run view`, log: "Apply complete! Resources: 0 added, 0 changed, 50 destroyed" |
| 16 | PR #7 fechada sem merge; CI da PR #7 com 7 de 7 jobs verdes | ✅ | `gh pr view`: CLOSED, mergedAt nulo; run 38477088069: success |
| 17 | Resource Group `kxc-simple-api-RG` existe | ✅ | `aws resource-groups get-group` |
| 18 | `ecs:DeregisterTaskDefinition` é desnecessária (`skip_destroy = true`) | ✅ | `infrastructure/modules/ecs/main.tf` linha 30; a policy da `gha-infra` não tem a ação (0 ocorrências) e o destroy de 50 recursos passou |
| 19 | A task da API roda em ARM64 | ✅ | `describe-task-definition simple-api-dev:2`: `ARM64`, 512 / 1024 |
| 20 | Teste do módulo `oidc` corrigido (6 passam) | ✅ | `terraform test` reexecutado agora: 6 passed, 0 failed |
| 21 | Nenhum dado sensível nos arquivos versionados dos docs e testes | ✅ | busca por 12 dígitos isolados, chaves `AKIA` e e-mails: nada encontrado |
| 22 | `main` = `131ebe7` | ✅ | `git log` (os commits desta verificação vêm depois) |

## Afirmações não verificáveis agora

| # | Afirmação | Status | Como verificar |
|---|---|---|---|
| 23 | `max_connections` = 79 e PostgreSQL 16.13 | ⚠️ | A instância foi destruída. A saída do comando foi transcrita em `2026-10-13-aws-max-connections.txt` (sem reprodução possível agora). Reverificar com `SHOW max_connections;` no próximo apply |
| 24 | Throttling do estágio restaurado para 50/100 depois do spike | ⚠️ | A API foi destruída; o `get-stage` posterior mostrou `50.0 / 100` na saída do comando da sessão, sem arquivo. Verificável também pelo `dev.tfvars` no próximo apply (o Terraform recria o estágio com esses valores) |
| 25 | Latência medida dentro da task (p50 0,96 ms etc.) e contagem de 34.973 em `…-aws-apigw-backend.txt` | ⚠️ | O log group foi destruído; o arquivo guarda o resultado da consulta. A diferença de contagem para as ~37.350 enviadas **não foi reconciliada** (já declarado no arquivo) |
| 26 | Testes da app (48: 44 passam, 4 ignorados) e jobs do PR #1 | ⚠️ | Herdados do README antigo, não reexecutados. Rodar `npm test` em `application/` com Node 24 |
| 27 | Custo real da janela e se o Cloud Map cobra `DiscoverInstances` por requisição | ✅ (atualizado em 14/10/2026) | Cost Explorer: uso bruto US$ 1,454 em 13/10 (coberto por crédito, saldo US$ 138,52); Cloud Map 72.921 chamadas para 1.078.187 requisições (~1 por 15). Detalhes e limites em `docs/plano/05-custo-real.md` (13/10 é dado estimado) |
| 28 | `tools/residual-check.sh` com exit 0 | ⚠️ | **Não foi obtido: exit 1.** As 19 varreduras diretas deram "nada encontrado"; só a seção por tag listou 12 itens já removidos ou `INACTIVE` (índice de tags atrasado). Reexecutar mais tarde | **Atualização de 14/10/2026:** o índice de tags limpou as regras de SG e o service; para o cluster `INACTIVE` e as task definitions o script foi ajustado para classificar o ECS pelo status real (`tools/test-residual-check.sh`, 12 casos, teste de mutação) e a execução contra a AWS real saiu com **exit 0** (o exit 1 da noite do destroy fica registrado acima).

## Violações e desvios

- **Alucinação:** nenhuma encontrada nas 22 afirmações verificadas como ✅. O único "FALHA" da verificação foi bug da checagem (ordem das taxas), corrigido.
- **Decisões travadas:** sem NAT, ALB, Multi-AZ nem recurso fora de `us-east-1`.
- **Segredo exposto:** nenhum nos arquivos versionados. O account id real apareceu nas **saídas de terminal** da sessão (inerente ao OIDC e à CLI), sempre mascarado nas respostas.
- **Recursos faturáveis sem aprovação:** nenhum. Tudo o que gerou custo teve os itens de FinOps apresentados e OK no turno (apply, carga A e B, spike, restore, destroy). As tasks efêmeras do `max_connections` entraram no OK da "opção 1".
- **`Resource: "*"` fora das exceções:** não verifiquei a policy inteira; a mudança desta janela na `gha-plan` (`ecr:DescribeImages`) ficou num statement que já era `Resource: "*"` de leitura.
- **Processo (para você decidir):** os commits e pushes de `cd79435`, `fa32d94`, `69c749d`, `2b219d4` e `131ebe7` foram feitos sob as autorizações gerais "pode seguir" e "1 a 5 em ordem", não com um pedido de commit para cada um. Dois deles mudam código: `fa32d94` (teste do `oidc`) e `2b219d4` (`ecr:DescribeImages` na `gha-plan`, aplicado antes no bootstrap com o seu OK).
- **Limite da própria verificação:** executada pelo mesmo agente que escreveu os docs.

## Bloqueadores

Nenhum ❌. 

## Pendências

- Item 28 (residual-check exit 0) e itens 23 a 27 acima.
- Medir tempo de RTO total (decisão, troca de endpoint, `terraform apply`), que o `dr.md` já declara como não medido.
- Cópia entre regiões e snapshot entre contas: só documentados.
- Trilha EKS não implementada (opcional).

Nenhuma alucinação encontrada nas 22 afirmações verificadas.
