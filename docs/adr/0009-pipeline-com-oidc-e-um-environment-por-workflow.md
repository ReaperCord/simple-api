# ADR 0009: Pipeline com OIDC e um environment por workflow

## Contexto

- O pipeline precisa de build e deploy automáticos, e o desafio avalia least privilege nas roles do pipeline. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Requisitos obrigatórios do desafio"]
- Sem environment, um workflow agendado na `main` teria o mesmo `sub` do deploy. Com um environment por workflow, o `sub` do token OIDC muda e uma role não é assumida pelo workflow de outra. [FATO: [`03-devsecops.md`](../../.kiro/steering/03-devsecops.md) seção "IAM"]
- As trust policies usam `sub` exato, sem curingas, e `aud = sts.amazonaws.com`. [FATO: [`modules/oidc/main.tf`](../../infrastructure/modules/oidc/main.tf) linhas 9-30]

| Role | `sub` aceito | Workflow |
|---|---|---|
| `gha-plan` | `repo:<GITHUB_OWNER>/simple-api:pull_request` | job `plan` do [`ci.yml`](../../.github/workflows/ci.yml), só para PR do mesmo repositório |
| `gha-deploy` | `repo:<GITHUB_OWNER>/simple-api:environment:deploy` | [`deploy.yml`](../../.github/workflows/deploy.yml) |
| `gha-infra` | `repo:<GITHUB_OWNER>/simple-api:environment:infra` | [`infra.yml`](../../.github/workflows/infra.yml), com aprovação manual |

  [FATO: [`modules/oidc/main.tf`](../../infrastructure/modules/oidc/main.tf) linhas 12-17]
- A role `gha-eks-lab` e o workflow `eks-lab.yml` estão previstos para o lab EKS e não existem. [FATO: [`bootstrap/main.tf`](../../infrastructure/bootstrap/main.tf) linha 74 (comentário "SEM gha-eks-lab")]
- Os workflows existentes:
  - `permissions` mínimas: `contents: read` por padrão e `id-token: write` só nos jobs que assumem role. [FATO: [`ci.yml`](../../.github/workflows/ci.yml) linhas 8-9 e 297-299, [`deploy.yml`](../../.github/workflows/deploy.yml) linhas 18-20, [`infra.yml`](../../.github/workflows/infra.yml) linhas 22-24]
  - As actions de terceiros estão fixadas por SHA de commit completo, com a tag em comentário. [FATO: [`deploy.yml`](../../.github/workflows/deploy.yml) linhas 40-45]
  - A imagem é construída uma vez, com tag igual ao SHA do commit, multi-arch (`linux/amd64,linux/arm64`). O push é pulado se a tag já existe no ECR (as tags são imutáveis). O scan e o deploy usam o digest gravado no ECR. [FATO: [`deploy.yml`](../../.github/workflows/deploy.yml) linhas 54-104]
  - O deploy espera o service estabilizar, roda o smoke test (`GET /` e `GET /connect` = 200) e, se falhar, volta o service à revisão anterior. [FATO: [`deploy.yml`](../../.github/workflows/deploy.yml) linhas 170-214]
  - `concurrency` impede dois deploys ao mesmo tempo. [FATO: [`deploy.yml`](../../.github/workflows/deploy.yml) linhas 22-24]
  - Nenhum `terraform apply` roda em `ci.yml` ou `deploy.yml`; só o `infra.yml` aplica, depois da aprovação do environment `infra`. [FATO: [`infra.yml`](../../.github/workflows/infra.yml) linhas 33 e 92-95]
- Cada environment aceita só a branch `main`, e só o `infra` exige aprovação. Os environments precisam ser criados no GitHub, e isso ainda não foi feito. [FATO: [`infrastructure/README.md`](../../infrastructure/README.md) linha 70 descreve o passo; o handoff de 13/10/2026 o lista como pré-requisito pendente]

## Decisão

Autenticar na AWS somente por OIDC, sem chaves de acesso de longo prazo, com uma role por workflow e um GitHub environment por workflow que assume role (`deploy` e `infra`; `eks-lab` quando o lab existir). A aprovação manual fica só no `infra`.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| Access keys do IAM em secrets do GitHub | Sem custo | Proibido: credencial de longo prazo |
| Uma única role para todos os workflows | Sem custo | Qualquer workflow assumiria permissão de apply |
| Aprovação obrigatória também no `eks-lab` | Sem custo | O `destroy` agendado travaria esperando alguém aprovar |
| CodePipeline, CodeBuild e CodeDeploy | **A verificar** | O repositório está no GitHub, e o Actions cobre o fluxo sem recursos extras na conta |

## Consequências

Riscos residuais conhecidos, registrados na revisão da fase A+B e ainda abertos:

- No `infra.yml` há um único job com o environment `infra`. A aprovação acontece antes de qualquer plan, e o aprovador libera o apply sem ter visto o plano. Separar `plan` e `apply` em dois jobs, com a aprovação depois do plan, é melhoria pendente. [FATO: [`infra.yml`](../../.github/workflows/infra.yml) linhas 31-95]
- A role `gha-infra` cria roles e policies com o prefixo `simple-api-*`. O conteúdo das policies criadas é livre, o que permite escalada de privilégio dentro do prefixo, e as policies não foram validadas com o IAM Access Analyzer (não foi verificado se o Free plan o libera nesta conta). Registrar como pendência antes do primeiro apply. [FATO: [`modules/oidc/main.tf`](../../infrastructure/modules/oidc/main.tf) linhas 51-52 e 519-554]
- O `aquasecurity/trivy-action` roda no job que tem credenciais AWS temporárias da `gha-deploy`. A action está fixada por SHA da v0.36.0. [FATO: [`deploy.yml`](../../.github/workflows/deploy.yml) linhas 106-137]
- O job `plan` do `ci.yml` executa `terraform plan` sobre o código do próprio PR com a role de leitura `gha-plan`. HCL do PR roda no runner com credenciais de leitura. Exigir aprovação de workflow para colaboradores e manter a role somente leitura. [FATO: [`ci.yml`](../../.github/workflows/ci.yml) linhas 291-299]
- As ações IAM de cada role contra um apply real não foram exercitadas. Suspeitos: VPC Link V2, Cloud Map, `secretsmanager` e `kms` do RDS. Nenhum workflow foi executado com as roles reais.

## Status

Aceito. Implementado nos workflows `ci.yml`, `deploy.yml`, `infra.yml` e no módulo `oidc`. Não executado contra a AWS.
