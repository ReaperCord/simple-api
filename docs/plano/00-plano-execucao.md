# Plano de execução: o que falta no KXC simple-api

Atualizado em 13/10/2026. Fork `ReaperCord/simple-api`, `main` = `aa2616e`. Fonte do estado: `handoff.md` (desatualizado em git), lista de pendências do Leandro e `.kiro/steering/`.

## Circuito de trabalho (vale para cada pacote)

| Fase | Quem | Saída | Gate humano |
|---|---|---|---|
| 1. Design | Claude no papel de `kxc-arquiteto` (e `kxc-iac`, `kxc-perf` quando couber) | Passos, comandos exatos, 5 itens de FinOps, critério de sucesso, rollback | — |
| 2. Review plan | Claude no papel de `kxc-verificador` + checklist de `02-finops-guardrails.md` | Tabela ✅ / ⚠️ / ❌ com evidência | Leandro aprova o plano |
| 3. Execute | Claude com o perfil `kxc-admin` do Leandro; Terraform numa branch nova | Saída dos comandos, arquivos alterados | Leandro dá OK no turno antes de cada apply, destroy ou comando que cobra |
| 4. Review final | Papel de `kxc-verificador` sobre diff e saída real; `tools/residual-check.sh` após destroy | "Nenhuma alucinação em N afirmações" ou lista de bloqueadores | Leandro fecha o pacote |

Regras fixas: sem commit/push/PR sem pedido; nunca `terraform -chdir` (usar `Set-Location`); account id, e-mail e segredo nunca em arquivo ou saída (`<AWS_ACCOUNT_ID>`); não editar `.kiro/**` nem `AGENTS.md`; todo relatório termina com arquivos alterados, comandos e resultado, o que não foi verificado e próximo passo.

## Pacotes

| WP | Pacote | Custo | Depende de | Status |
|---|---|---|---|---|
| 0 | Reaplicar o bootstrap (policy `gha-infra`) | zero (só IAM) | WP1 | **Concluído em 13/10/2026**: apply 0 added / 1 changed / 0 destroyed (policy `gha-infra`); novo plan sem diferenças; `boot.tfplan` apagado |
| 1 | Auditar a policy `gha-infra` contra os recursos que ainda faltam criar (service ECS, autoscaling, RDS, Cloud Map, alarmes, secret); inclui `ecs:DeregisterTaskDefinition` (2.1) e secret/KMS do RDS (2.4) | zero | — | **Concluído** (ver `01-wp1-auditoria-iam.md`): nenhum patch novo; 2.1 desnecessária por `skip_destroy = true` |
| 2 | Completar o apply da stack via `infra.yml` (gate `infra`) | ~US$ 34/mês 24x7 | WP0, 5 itens de FinOps, OK no turno | **Concluído 13/10/2026**: run 38459253681, 17 added / 0 changed / 1 destroyed, sem AccessDenied (janela aberta ~20h UTC) |
| 3 | Pós-apply: variable `API_URL`, smoke de `/`, `/health`, `/connect`, `deploy.yml` de ponta a ponta, evidências | baixo | WP2 | **Parcial**: `API_URL` criada; `/`, `/health`, `/connect` = 200; falta `deploy.yml` e evidências restantes |
| 4 | Carga na AWS (dentro da VPC e pelo API Gateway); conferir cobrança do Cloud Map por `DiscoverInstances` | por requisição (calcular antes) | WP3 | Pendente |
| 5 | Destroy + `residual-check.sh` (exit 0) ao fim de cada janela | zero | — | A cada janela |
| 6 | README "Pendências", `infrastructure/README.md` linha 43 (ADR 0012), higiene (CRLF, alarmes sem destino), repo privado no fim | zero | Resultados reais | Pendente |
| Opc. | Benchmark local (branch só no PC original) e lab EKS | — | — | Se sobrar tempo |

## Ordem

1. WP1 completo (design → review → OK → patch em branch).
2. WP0 e WP2 juntos, com os 5 itens de FinOps. O item 5 (Free plan aceita criar Fargate, API Gateway e Cloud Map?) é DESCONHECIDO: considerar um smoke barato antes da stack inteira.
3. WP3 → WP4 → WP5, depois WP6.

## Pontas abertas

- Terraform 1.16.5 está em `%LOCALAPPDATA%\Programs\terraform-1.16.5\`; o do PATH é o 1.14.3.
- `gh auth login` como ReaperCord ainda é necessário antes do WP2.
- `bash` do PATH é WSL; usar o Git Bash para `tools/residual-check.sh`.
- O state do bootstrap é sensível e só existe em duas máquinas: manter backup fora do git.
