# ADR 0009: Pipeline com OIDC e um environment por workflow

## Contexto

- O pipeline precisa de build e deploy automáticos, e o desafio avalia least privilege nas roles do pipeline. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Requisitos obrigatórios do desafio"]
- Sem environment, um workflow agendado na `main` teria o mesmo `sub` do deploy. Com um environment por workflow (ou por job), o `sub` do token OIDC muda e uma role não é assumida pelo workflow de outra. [FATO: [`03-devsecops.md`](../../.kiro/steering/03-devsecops.md) seção "IAM"]
- As trust policies usam `sub` exato, sem curingas, e `aud = sts.amazonaws.com`. Cada role aceita dois formatos do mesmo `sub`, o por nome e o imutável (`OWNER@ID/REPO@ID`). [FATO: [`modules/oidc/main.tf`](../../infrastructure/modules/oidc/main.tf), `locals`]

| Role | `sub` aceito (contexto) | Onde roda |
|---|---|---|
| `gha-plan` | `pull_request` | job `plan` do [`ci.yml`](../../.github/workflows/ci.yml), só para PR do mesmo repositório |
| `gha-deploy` | `environment:deploy` | [`deploy.yml`](../../.github/workflows/deploy.yml) |
| `gha-infra-plan` | `environment:infra-plan` | job `plan` do [`infra.yml`](../../.github/workflows/infra.yml), sem aprovação |
| `gha-infra` | `environment:infra` | job `apply` do [`infra.yml`](../../.github/workflows/infra.yml), com aprovação manual |
| `gha-eks-lab` | `environment:eks-lab` | [`eks-lab.yml`](../../.github/workflows/eks-lab.yml), sem aprovação (o destroy por TTL precisa rodar sozinho) |

- Os workflows:
  - `permissions` mínimas: `contents: read` por padrão e `id-token: write` só onde há role a assumir.
  - As actions de terceiros estão fixadas por SHA de commit completo, com a tag em comentário.
  - A imagem é construída uma vez, com tag igual ao SHA do commit, multi-arch (`linux/amd64,linux/arm64`). O push é pulado se a tag já existe no ECR (as tags são imutáveis). O scan e o deploy usam o digest gravado no ECR.
  - O deploy espera o service estabilizar, roda o smoke test (`GET /` e `GET /connect` = 200) e, se falhar, volta o service à revisão anterior.
  - `concurrency` impede dois deploys, ou dois runs do `infra.yml`, ao mesmo tempo.
  - Nenhum `terraform apply` da stack principal roda em `ci.yml` ou `deploy.yml`. Só o job `apply` do `infra.yml` aplica, e só depois da aprovação do environment `infra`.
- **`infra.yml` em dois jobs (desde 14/10/2026):**
  1. **`plan`** (`gha-infra-plan`, sem gate):
     - Gera o plano e publica no resumo do run as contagens e a lista do que será destruído ou substituído. A classificação é feita por [`tools/plan-guard.sh`](../../tools/plan-guard.sh), com teste no CI.
     - Se houver `delete` ou `replace` em `apply` ou `destroy`, exige `confirm_destructive=dev`. Sem isso, o run para antes do gate.
     - Guarda o plano em `plans/<run>/tfplan` no bucket de state (privado, criptografado, expira em 7 dias) e registra o SHA-256.
  2. **`apply`** (`gha-infra`, gate `infra`):
     - Só roda em `apply` ou `destroy` com mudança.
     - Baixa o plano, confere o SHA-256 e aplica exatamente esse plano. O Terraform recusa o arquivo se o state mudou depois do plan.
- A `gha-infra-plan` tem as mesmas leituras da `gha-plan`, mais `s3:PutObject` só em `plans/*`. A `gha-infra` ganhou só `s3:GetObject` em `plans/*`. As leituras da `gha-plan` já tinham sido exercitadas pelo `plan` do CI com a stack no ar.
- Os environments `deploy`, `infra`, `infra-plan` e `eks-lab` existem no GitHub e aceitam só a branch `main`. Só o `infra` exige aprovação. O secret da `gha-infra-plan` fica no environment `infra-plan`, e não no repositório.

## Decisão

Autenticar na AWS somente por OIDC, sem chaves de acesso de longo prazo, com uma role por workflow (ou por job, no `infra.yml`) e um GitHub environment para cada contexto que assume role. A aprovação manual fica só no `infra` e acontece **depois** de o plano existir.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| Access keys do IAM em secrets do GitHub | Sem custo | Proibido: credencial de longo prazo |
| Uma única role para todos os workflows | Sem custo | Qualquer workflow assumiria permissão de apply |
| Aprovação obrigatória também no `eks-lab` | Sem custo | O `destroy` agendado travaria esperando alguém aprovar |
| Reusar a `gha-plan` no job `plan` do `infra.yml` | Sem custo | A `gha-plan` roda HCL vindo de PR; dar escrita a ela, mesmo restrita a `plans/*`, aumentaria a superfície |
| Plano como artifact do GitHub | Sem custo | O repositório é público e o plano carrega dados do ambiente (account id, endereços) |
| CodePipeline, CodeBuild e CodeDeploy | **A verificar** | O repositório está no GitHub, e o Actions cobre o fluxo sem recursos extras na conta |

## Consequências

Riscos residuais conhecidos:

- (Resolvido em 14/10/2026) O `infra.yml` tinha um único job, e a aprovação vinha antes do plan. Hoje o aprovador lê o plano antes de aprovar, e plano destrutivo exige confirmação explícita. **Exercitado no GitHub em 14/10/2026**, com a stack destruída:
  - `action=plan` (run 38669868242): 54 a criar, não destrutivo; `apply` pulado.
  - `action=destroy` com o state vazio (run 38669878847): sem mudanças; `apply` pulado, sem pedir gate.
  - `action=apply` (run 38670814968): o plano foi guardado no bucket. Conferido à parte: 62.107 bytes, AES256, SHA-256 `3dfc8431…` calculado sobre o arquivo baixado. A comparação com o hash do resumo do run é visual (a API não expõe o resumo do job). O `apply` ficou no gate, e o gate foi **rejeitado**: nenhum passo rodou e nada foi criado.
- **Ainda não exercitado no GitHub:**
  - o download, a conferência do hash e o apply do job `apply`, que ficam para o próximo apply real;
  - o bloqueio por `confirm_destructive`, que precisa de state com recursos. Foi validado localmente com um plano destrutivo real (`terraform_data`, 1 replace e 1 delete) e por 9 testes no CI.
- A confirmação destrutiva é um texto fixo (`dev`). Ela evita o clique automático, mas não substitui ler a lista.
- A role `gha-infra` cria roles e policies com o prefixo `simple-api-*`. O conteúdo das policies criadas é livre, o que permite escalada de privilégio dentro do prefixo, e as policies não foram validadas com o IAM Access Analyzer.
- O `aquasecurity/trivy-action` roda no job que tem credenciais AWS temporárias da `gha-deploy`.
- O job `plan` do `ci.yml` executa `terraform plan` sobre o código do próprio PR com a role de leitura `gha-plan`. Manter a role somente leitura e a aprovação de workflow para colaboradores.
- As roles foram exercitadas contra a AWS nas janelas de 13 e 14/10/2026. Cada permissão que faltou foi adicionada com o motivo em comentário (least privilege iterativo).

## Status

Aceito. Implementado nos workflows `ci.yml`, `deploy.yml`, `infra.yml`, `eks-lab.yml` e no módulo `oidc`, e executado contra a AWS. O fluxo de dois jobs do `infra.yml` foi validado até o gate. O apply do plano revisado fica para a próxima janela de AWS.
