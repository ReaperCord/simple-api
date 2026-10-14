# Laboratório EKS: runbook

Decisões e desvios da steering: [ADR 0014](adr/0014-lab-eks-com-argo-cd-core-e-nlb-interno.md). Estado: manifests e Terraform **validados localmente e em CI**; **nunca aplicado na AWS**.

## O que é

Um cluster EKS efêmero (vida máxima de 6 h) que roda a mesma API da trilha ECS, atrás do **mesmo API Gateway** (rotas `/eks`), com Argo CD (core) e o AWS Load Balancer Controller. Custo estimado ~US$ 0,17/h só do lab (plano de controle em suporte padrão mais nós), mais a stack principal no ar. Sempre destruir ao fim.

```text
Internet ─► API Gateway (stage $default)
              ├─ $default ──────────────► VPC Link ─► Cloud Map ─► ECS Fargate
              └─ ANY /eks, /eks/{proxy+} ► VPC Link ─► NLB interno ─► pods (EKS)  ──► RDS (IAM, app_connect)
```

## Teste local (custo zero)

```bash
tools/k8s-local-test.sh        # kind + metrics-server + overlay local; ~10 min; exit 0 = tudo passou
```

Cobre: contrato HTTP, uid 1000 e FS somente leitura, Pod Security `restricted`, HPA lendo CPU e escalando sob carga, PDB, e 3 rolling restarts sem nenhuma requisição falhada. Exige o daemon do Docker ligado. Não toca a AWS e só mexe no cluster `simple-api-local` do kind.

## Pré-requisitos para subir na AWS (uma vez)

1. **Bootstrap**: aplicar a role `gha-eks-lab` (`infrastructure/bootstrap`, plano de 5 recursos de IAM, custo zero).
2. **GitHub**: environment `eks-lab` (só a branch `main`, **sem** aprovação) e o secret `AWS_EKS_LAB_ROLE_ARN`. Opcional: o secret `EKS_LAB_ADMIN_ARNS` (lista JSON de ARNs IAM com acesso de administrador ao cluster, ex.: `["arn:aws:iam::<conta>:user/<usuario>"]`).
3. **Stack principal no ar** (`infra.yml apply`) e **imagem no ECR** (o `deploy.yml` publica a tag do commit).
4. A variable `API_URL` do GitHub apontando para a API da stack.

## Subir e descer

```bash
gh workflow run eks-lab.yml -f action=up -f image_tag=<SHA da imagem no ECR>
gh workflow run eks-lab.yml -f action=down
```

`up`: Terraform etapa 1 (cluster, nós, add-ons, Pod Identity, regras do lab) → controller (helm) → Argo CD core → ConfigMap do banco e `Application` → espera Synced/Healthy e o NLB → Terraform etapa 2 (rotas `/eks`) → smoke `GET /eks/health` e `/eks/connect`.
`down`: apaga o `Application`, o `Service` (o controller remove o NLB), desinstala o controller e roda o `terraform destroy`.

O agendamento horário **destrói** o lab depois do TTL gravado na tag do cluster. Depois de qualquer destroy: `tools/residual-check.sh`.

## O que provavelmente precisa de ajuste na primeira vez

| Ponto | Sintoma | Onde mexer |
|---|---|---|
| Formato do `overwrite:path` | `/eks/health` devolve 404 ou 5xx | `infrastructure/eks-lab/apigw.tf` (`request_parameters`) |
| Saída do VPC Link até o NLB | `/eks/*` dá 5xx/timeout | regra `vpclink_to_nlb`; SG do NLB criado pelo controller |
| Permissão faltando na `gha-eks-lab` | `AccessDenied` no apply | `infrastructure/modules/oidc/main.tf` (policies `eks_lab` e `eks_lab_iam`); ciclo: ler a ação, adicionar com comentário, reaplicar o bootstrap |
| Memória dos nós | pods `Pending` ou reiniciando | `node_instance_type` (`t4g.small` tem 2 GiB) |
| Pod sem banco | `CreateContainerConfigError` | o ConfigMap `simple-api-db` (criado pelo workflow) |
