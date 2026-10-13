# ADR 0008: Terraform com roots separados (bootstrap, principal e eks-lab)

## Contexto

- Toda a infraestrutura base precisa ser criada por Terraform. Deploy manual pelo console não é avaliado. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Requisitos obrigatórios do desafio"]
- Algumas coisas precisam existir antes da stack: o bucket do state remoto, o repositório ECR (a task precisa de uma imagem publicada), o provider OIDC e as roles do pipeline, e o budget (a steering manda criar o budget antes do primeiro apply da stack). [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Orçamento e estimativas" e [`04-terraform.md`](../../.kiro/steering/04-terraform.md) regra 4]
- O root `bootstrap` cria o bucket de state (versionamento, SSE-S3, bloqueio de acesso público), o ECR, o budget e o OIDC. O state do bootstrap é local e sensível. [FATO: [`infrastructure/bootstrap/main.tf`](../../infrastructure/bootstrap/main.tf) linhas 1-90]
- O root principal usa backend S3 parcial com `use_lockfile = true` e `encrypt = true`. Bucket, chave e região entram por `-backend-config`. [FATO: [`infrastructure/versions.tf`](../../infrastructure/versions.tf) linhas 11-16]
- Versões: `required_version >= 1.11` e provider `hashicorp/aws ~> 6.68`, com lockfile versionado em 6.68.0 para as plataformas `windows_amd64`, `linux_amd64`, `linux_arm64` e `darwin_arm64` em cada root. [FATO: [`versions.tf`](../../infrastructure/versions.tf) e [`infrastructure/README.md`](../../infrastructure/README.md) linha 64]
- O estado do bootstrap é local, então a stack principal lê o ECR por nome com um data source, não por remote state. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 24-26]
- O root `infrastructure/eks-lab/` está previsto na steering e não existe ainda. [FATO: listagem do repositório em 13/10/2026]
- Os roots usam `default_tags` com `Project`, `Env`, `Track`, `Owner`, `ManagedBy` e `TTL`. O bootstrap usa `Track=bootstrap`, que a varredura de resíduos ignora. [FATO: [`infrastructure/providers.tf`](../../infrastructure/providers.tf) e [`bootstrap/providers.tf`](../../infrastructure/bootstrap/providers.tf)]

## Decisão

Dividir o Terraform em roots independentes: `infrastructure/bootstrap/` (aplicado uma vez, com state local), `infrastructure/` (stack principal, com state em S3) e, quando existir, `infrastructure/eks-lab/` (lab efêmero). Os módulos ficam em `infrastructure/modules/` e são reaproveitados e corrigidos, não substituídos por módulos da Registry.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| Root único com tudo | Sem custo | O `destroy` da stack levaria junto o bucket de state, o ECR e o budget. A imagem precisa existir antes do apply da stack |
| CDK ou CloudFormation | Sem custo | A decisão do projeto é Terraform. [FATO: [`09-aws-agent-toolkit.md`](../../.kiro/steering/09-aws-agent-toolkit.md) seção "Precedência"] |
| Trava de state com DynamoDB | Custo da tabela, **a verificar** | Os argumentos de DynamoDB do backend S3 estão depreciados no Terraform 1.11 em favor de `use_lockfile`. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Fatos de serviços AWS"] |
| Módulos da Registry no lugar dos módulos do repositório | Sem custo | A regra 1 de [`04-terraform.md`](../../.kiro/steering/04-terraform.md) manda corrigir os módulos existentes |

## Consequências

- Ordem obrigatória do primeiro uso: bootstrap (local, com aprovação), depois `deploy.yml` com `only_build=true` para publicar a primeira imagem, depois `infra.yml` para criar a stack. Sem a imagem, a task não sobe. [FATO: [`infra.yml`](../../.github/workflows/infra.yml) linhas 1-3 e [`06-cicd.md`](../../.kiro/steering/06-cicd.md) regra 6]
- O `terraform.tfstate` do bootstrap fica só na máquina de quem aplicou. Se for perdido, o bootstrap não é gerenciável sem importar os recursos. O arquivo é sensível e nunca deve ser versionado nem aberto. [FATO: [`.gitignore`](../../.gitignore) linhas 22-25]
- O `terraform destroy` da stack principal não remove o bootstrap (bucket, ECR, budget, OIDC). Esses recursos seguem cobrando, embora pouco. Preço do bootstrap: **a verificar**.
- A convenção de nomes `<projeto>-<ambiente>` é duplicada nos dois roots (`local.name`), e o OIDC do bootstrap monta os ARNs de cluster, service e roles da task a partir dela. [FATO: [`main.tf`](../../infrastructure/main.tf) e [`bootstrap/main.tf`](../../infrastructure/bootstrap/main.tf) linhas 8-15]
- O bootstrap tem uma variável `environment` única, então as roles do pipeline operam os nomes de um ambiente (`dev` por padrão). O `deploy.yml` tem cluster e service `simple-api-dev` fixos. Operar `hml` ou `prod` exige novo bootstrap e ajuste do workflow. [FATO: [`bootstrap/variables.tf`](../../infrastructure/bootstrap/variables.tf) linhas 7-16 e [`deploy.yml`](../../.github/workflows/deploy.yml) linhas 26-31]
- Os módulos não têm lockfile próprio. O CI copia o lockfile do root para validar cada módulo. [FATO: [`ci.yml`](../../.github/workflows/ci.yml) linhas 155-170]
- O `terraform plan` e o `apply` com backend real nunca rodaram. Os data sources `aws_availability_zones` e `aws_ecr_repository` só resolvem na AWS.

## Status

Aceito. Implementado para `bootstrap` e `infrastructure`. O root `eks-lab` não foi implementado.
