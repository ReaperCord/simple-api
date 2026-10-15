# Laboratório EKS: runbook

Decisões e desvios da steering: [ADR 0014](adr/0014-lab-eks-com-argo-cd-core-e-nlb-interno.md). Estado: validado localmente, em CI e **na AWS em 14/10/2026** (janela 3, dados em [`tests/k8s/2026-10-14-eks-janela-3-resultado.txt`](../tests/k8s/2026-10-14-eks-janela-3-resultado.txt)).

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

O agendamento horário **destrói** o lab depois do TTL gravado na tag do cluster. **Não conte com ele:** na janela 3 rodou uma vez só em 5 h de lab (o GitHub atrasa ou pula `schedule`). Sempre rode o `down` ao terminar. Depois de qualquer destroy: `tools/residual-check.sh`.

Tempos medidos (janela 3, criação do run até o fim): `up` do zero ~13 min até a etapa 2 (run 38645357389); `down` ~12 e ~9 min (runs 38643645498 e 38663075875). Rodar o `up` de novo com o lab no ar não recria nada da etapa 1.

## Problemas já encontrados (e corrigidos) na AWS

| Sintoma | Causa | Correção |
|---|---|---|
| `CreateNodegroup`: `missing permissions for 'iam:GetRole'` | o EKS confere a role de serviço do node group; para role inexistente o IAM avalia o ARN **sem path** | `IamReadServiceLinkedRolesEks` em `modules/oidc/main.tf` |
| `CreatePodIdentityAssociation`: `not authorized to perform: iam:PassRole` | Pod Identity passa a role para `pods.eks.amazonaws.com` | `iam:PassedToService` inclui esse serviço |
| helm ou Argo CD: `the server is currently unable to handle the request` | **metrics-server v0.9.0** corrompe o `/openapi/v2` (protobuf dá 503) | add-on em v0.8.1 (`variables.tf`; teste barra v0.9.x) |
| `Application referencing project default which does not exist` | o Argo CD core não cria o projeto `default` | AppProject `simple-api` criado pelo workflow |
| etapa 2: `DescribeLoadBalancerAttributes` negado | o `data.aws_lb` chama essa ação | adicionada à policy `eks_lab` |
| smoke: `GET /eks/health -> 404` logo após a etapa 2 | rotas novas levam alguns segundos para publicar no stage `$default` | smoke repete por até 120 s |
| timeouts no rolling restart | pod novo `Ready` antes de estar no target group; cross-zone do NLB desligado | readiness gate (label do namespace) e `load_balancing.cross_zone.enabled=true` |

Para diagnosticar o `/openapi/v2` (se aparecer de novo com outra versão de add-on):

```bash
TOKEN=$(aws eks get-token --cluster-name simple-api-dev-eks --query status.token --output text)
EP=$(aws eks describe-cluster --name simple-api-dev-eks --query cluster.endpoint --output text)
curl -sk -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" \
  -H 'Accept: application/com.github.proto-openapi.spec.v2@v1.0+protobuf' "$EP/openapi/v2"   # esperado: 200
```

## Pontos a observar

| Ponto | Sintoma | Onde mexer |
|---|---|---|
| Permissão faltando na `gha-eks-lab` | `AccessDenied` no apply | `infrastructure/modules/oidc/main.tf` (policies `eks_lab` e `eks_lab_iam`); antes de corrigir, confirmar com `aws iam simulate-principal-policy` e, para data sources, com `TF_LOG=DEBUG` (lista as chamadas reais) |
| Memória dos nós | pods `Pending` ou reiniciando | `node_instance_type` (`t4g.small` tem 2 GiB; medido 49% e 65% com tudo no ar) |
| Pod sem banco | `CreateContainerConfigError` | o ConfigMap `simple-api-db` (criado pelo workflow) |
| Resíduo no rolling restart | 1 falha em 788 com cross-zone ligado | não investigado |
