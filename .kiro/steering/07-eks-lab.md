---
inclusion: fileMatch
fileMatchPattern: ["k8s/**", "infrastructure/eks-lab/**"]
---

# Laboratório EKS + Argo CD

## Ordem

1. kind ou k3d LOCAL primeiro: manifests, probes, metrics-server, HPA, Argo CD. Custo zero.
2. Só depois o EKS na AWS, com aprovação, custo estimado (~US$ 0,17/h) e o plano da conta confirmado.
3. Ao terminar: `terraform destroy` do `eks-lab` + `tools/residual-check.sh`.

## Manifests (Kustomize: `k8s/base`, `k8s/overlays/{local,eks}`)

- Deployment: `requests` = `limits` de CPU 500m (paridade com a task Fargate de 0,5 vCPU) e memória 256Mi; `readinessProbe` e `livenessProbe` em `/health` (nunca em `/connect`); `RollingUpdate` com `maxUnavailable: 0` e `maxSurge: 1` (o surge entra na conta de conexões do banco).
- `DB_POOL_MAX=3` (regra de conexões em `01-arquitetura-e-restricoes.md`).
- `securityContext`: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`.
- PodDisruptionBudget `minAvailable: 1`. HPA CPU 60%, min 1, max 3 (exige metrics-server).
- Segredo do banco: a app lê do Secrets Manager (`DB_SECRET_ARN`) com Pod Identity da própria app, ou External Secrets / CSI driver — escolha e documente; nunca um `Secret` com valor no Git.
- Service do tipo LoadBalancer para NLB **interno** via AWS Load Balancer Controller. Confira os nomes exatos das anotações na doc da versão instalada do controller e cite — não chute.

## Infra do lab

- `infrastructure/eks-lab/` é root separado. Lê VPC/subnets/SG do RDS via `terraform_remote_state`. Nunca altera a stack principal (precisa de regra no SG do RDS? peça ao `kxc-iac`).
- Managed node group em subnets públicas com auto-assign de IPv4 público ligado (obrigatório).
  - Free plan: 2–3 × `t4g.small` on-demand (2 GiB, ~11 pods por nó com o VPC CNI padrão).
  - Paid plan: 2 × `t4g.medium` Spot, tipos diversificados.
- Sem Fargate profile. Sem NAT. Add-ons: VPC CNI, CoreDNS, kube-proxy, EKS Pod Identity Agent, metrics-server.
- Argo CD só com componentes core (desligar dex e notifications) para caber nos nós.
- LB Controller com `config/policies/alb_controller_policy.json` via Pod Identity (ou IRSA se a versão do controller exigir — conferir).
- API Gateway: `ANY /eks/{proxy+}` e `ANY /eks` → VPC Link → NLB, com `overwrite:path` a partir de `$request.path.proxy` (testar o formato; a doc não traz exemplo com integração privada).
- Tag `TTL` com horário de expiração; `eks-lab.yml` agendado (environment `eks-lab`, sem aprovação obrigatória) destrói clusters vencidos.

## GitOps

Argo CD observa `k8s/overlays/eks` na branch `gitops`. O CI só altera a tag da imagem no `kustomization.yaml` do overlay nessa branch (a `main` é protegida por PR e rejeitaria o push do `GITHUB_TOKEN`). Rollback = `git revert` na `gitops`. Nunca `kubectl apply` manual no cluster gerido pelo Argo, exceto na instalação do próprio Argo.
