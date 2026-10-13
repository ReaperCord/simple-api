---
inclusion: fileMatch
fileMatchPattern: [".github/**"]
---

# Padrões de CI/CD (GitHub Actions)

## Workflows previstos

| Arquivo | Gatilho | Environment | Role AWS |
|---|---|---|---|
| `ci.yml` | `pull_request` | — | `gha-plan` (leitura + `.tflock`) |
| `deploy.yml` | `push` na `main` com paths `application/**`; `workflow_dispatch` com `only_build=true` para publicar a primeira imagem | `deploy` | `gha-deploy` |
| `infra.yml` | `workflow_dispatch` | `infra` (com aprovação) | `gha-infra` |
| `eks-lab.yml` | `workflow_dispatch` (`up`/`down`) + `schedule` horário (destrói cluster > 6 h) | `eks-lab` | `gha-eks-lab` |

## Regras

1. Autenticação AWS SOMENTE por OIDC (`aws-actions/configure-aws-credentials` com `role-to-assume`). Nunca `AWS_ACCESS_KEY_ID` em secrets.
2. Um GitHub environment por workflow que assume role: o `sub` do token vira `repo:<owner>/<repo>:environment:<nome>` e cada trust policy aceita só o seu. Cada environment aceita só a branch `main`. Aprovação obrigatória só no `infra`: no `eks-lab` ela travaria o destroy agendado esperando alguém aprovar.
3. `permissions:` mínimas por workflow/job (`id-token: write` só onde assume role; `contents: read` padrão).
4. Actions de terceiros fixadas por SHA de commit completo, com a tag em comentário. Verifique o SHA no repositório da action — não invente. Se não conseguir verificar, deixe `# TODO: verificar SHA`.
5. Imagem construída UMA vez, tag = `${{ github.sha }}`, multi-arch (`linux/amd64,linux/arm64`). Tags do ECR imutáveis → antes do push, checar se a tag já existe (re-run do mesmo SHA) e pular o push.
6. **Ordem do primeiro deploy:** o ECR nasce no `bootstrap`; `deploy.yml` com `only_build=true` publica a primeira imagem; só então o `infra.yml` cria a stack apontando para essa tag. Sem isso a task não sobe e o smoke test falha.
7. Deploy usa exatamente a imagem escaneada. Sem rebuild entre scan e deploy. A action oficial de deploy no ECS (`aws-actions/amazon-ecs-deploy-task-definition`, major `v2`) documenta as permissões mínimas — siga-as.
8. Após o deploy, esperar o service estabilizar e rodar smoke test (`GET /` e `GET /connect` = 200). Falha → reaplicar a revisão anterior e falhar o job.
9. **GitOps sem furar a proteção da `main`:** a tag da imagem do EKS é commitada na branch `gitops` (que o Argo CD observa e só o workflow escreve), não na `main` protegida por PR. Rollback = `git revert` nessa branch.
10. `pull_request` de fork nunca recebe `id-token: write` nem secrets.
11. `concurrency` no deploy para não rodar dois deploys simultâneos.
12. Nada de `terraform apply` em `ci.yml` ou `deploy.yml`. No `ci.yml`, `terraform plan` usa a trava do S3 (a role precisa de Get/Put/Delete só no `.tflock`).

## Anti-alucinação

Inputs de actions (`with:`) precisam existir no `action.yml` da versão fixada. Se não tiver certeza, abra o `action.yml` e cite. Valide os workflows com `actionlint` antes de declarar pronto.
