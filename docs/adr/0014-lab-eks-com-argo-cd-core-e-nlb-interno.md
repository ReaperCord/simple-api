# ADR 0014: laboratório EKS efêmero (Argo CD core, NLB interno pelo mesmo API Gateway)

Complementa o [ADR 0007](0007-eks-somente-como-laboratorio-efemero.md) (EKS só como lab efêmero) com as decisões de implementação.

## Contexto

- A trilha ECS é a principal. O EKS entra como diferencial, num root Terraform separado (`infrastructure/eks-lab`), com vida máxima de 6 h, e **nunca altera** a stack principal. [FATO: [`07-eks-lab.md`](../../.kiro/steering/07-eks-lab.md), [ADR 0008](0008-terraform-com-roots-separados.md)]
- Versões do Kubernetes em **suporte padrão** em 14/10/2026: 1.34 a 1.37, padrão 1.36 (fim do suporte padrão em 01/08/2027). A 1.33 e as anteriores já estão em suporte estendido (US$ 0,60/h, proibido). [FATO: `aws eks describe-cluster-versions`, 14/10/2026]
- Add-ons do EKS disponíveis para a 1.36: VPC CNI v1.23.2, CoreDNS v1.14.7, kube-proxy v1.36.0, Pod Identity Agent v1.4.0 e **metrics-server v0.9.0** (o HPA depende dele). [FATO: `aws eks describe-addon-versions`, 14/10/2026]
- O NLB interno vem do AWS Load Balancer Controller, com as anotações `aws-load-balancer-type: external`, `nlb-target-type: ip` e `scheme: internal`. [FATO: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/annotations/, aberta em 14/10/2026] Chart `eks/aws-load-balancer-controller` 3.6.0 (app v3.6.0). [FATO: `helm search repo`, 14/10/2026]
- O repositório é **público** e a regra do projeto proíbe account id em arquivo.

## Decisão

1. **Kustomize em `k8s/`**: `base` (Deployment, Service, HPA, PDB, ServiceAccount, namespace com Pod Security `restricted`) e dois overlays: `local` (kind, com um Postgres) e `eks`. Deployment com `requests = limits` de CPU 500m (paridade com a task Fargate), probes em `/health`, `RollingUpdate` com `maxUnavailable: 0`, `preStop` de 8 s, `securityContext` restrito e HPA CPU 60%, min 1, max 3.
2. **Root `infrastructure/eks-lab`**: cluster com `upgrade_policy = STANDARD` (impede o suporte estendido), autenticação só por API (access entries), nós `t4g.small` ARM64 on-demand em subnets **públicas** (sem NAT e sem Fargate), os 5 add-ons com versão fixada, Pod Identity para o controller e para a app. Lê a stack principal por `terraform_remote_state`. O que o lab precisa na stack principal entra como **recurso próprio do lab** e some no destroy: regra de SG do RDS, regra de SG nos pods, tags das subnets privadas e as rotas `ANY /eks` e `ANY /eks/{proxy+}` (etapa 2).
3. **App no EKS com a autenticação IAM do ADR 0013**: o pod usa o usuário `app_connect` e as credenciais vêm do Pod Identity (a role só tem `rds-db:connect` nesse usuário e instância). Nenhum segredo no cluster.
4. **Role `gha-eks-lab`** (módulo `oidc`): só o `sub` `environment:eks-lab` a assume; policy dividida em duas (EKS/EC2/ELB/API Gateway/state e IAM), cada ação justificada; só mexe em roles e policies `<projeto>-*-eks-*` e anexa só 4 políticas gerenciadas da AWS.
5. **Workflow `eks-lab.yml`**: `up`, `down` e um agendamento horário que destrói o lab vencido (TTL gravado na tag do cluster). Sem aprovação (o destroy agendado precisa rodar sozinho). No `down`, apaga primeiro o Application e o Service (o controller remove o NLB) e desinstala o controller antes do `terraform destroy`; senão o NLB e o SG ficam órfãos e travam o destroy da VPC.
6. **Argo CD só com os componentes core** (v3.5.5), observando `k8s/overlays/eks` na `main`.

### Desvios da steering (registrados, não corrigidos nos arquivos de `.kiro`, que só o Leandro edita)

| Steering | O que foi feito | Por quê |
|---|---|---|
| `06-cicd.md` regra 9 e `07-eks-lab.md`: Argo CD observa a branch **`gitops`** e o CI commita a tag da imagem nela | O Argo CD observa a **`main`**; o registro e a tag da imagem entram como parâmetro (`kustomize.images`) do `Application`, criado pelo workflow em runtime. Não há branch `gitops` nem commit de CI | O registro ECR tem o **account id** e o repositório é público: nenhum arquivo versionado pode conter a imagem completa. A `main` deste fork também não é protegida por PR, que era o motivo da branch separada |
| `07-eks-lab.md`: rollback = `git revert` na `gitops` | Rollback = reaplicar o `Application` com a tag anterior (o `deploy`/`up` recebe a tag como entrada) | Consequência do ponto acima; o histórico fica nas execuções do workflow |
| `07-eks-lab.md`: manifest do banco | `ConfigMap simple-api-db` criado pelo workflow a partir dos outputs do Terraform, não versionado | O hostname do RDS muda a cada apply; sem o ConfigMap o pod fica em `CreateContainerConfigError` (sinal esperado) |

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| Fargate no EKS, EKS Auto Mode, Karpenter | maior | Proibidos pela steering (Fargate exige subnet privada, logo NAT) |
| Nós `t4g.medium` Spot | menor que on-demand | Só no Paid plan; o Free plan usa `t4g.small` on-demand |
| Branch `gitops` com a tag no Git | zero | Exigiria o account id no repositório público |
| Rota do lab por um segundo API Gateway | US$ 1,00/milhão + novo VPC Link | A steering manda reaproveitar o mesmo API Gateway e o VPC Link V2 |
| Criptografia de secrets do cluster e logs do plano de controle | custo mensal da chave KMS e dos logs (a verificar) | Lab efêmero sem segredos no cluster; registrado em `infrastructure/.trivyignore` quando o Trivy apontar |

## Consequências

- **Validado só localmente (kind) e em CI; ainda não aplicado na AWS.** Teste local com Kubernetes 1.35: contrato HTTP, uid 1000, FS somente leitura, Pod Security `restricted` barrando pod privilegiado, HPA com metrics-server v0.9.0 e escala sob carga, PDB e rolling update sem falhas. Esse teste **encontrou uma falha real**: sem `preStop`, 1 requisição em 358 falhou num rolling restart (o pod que sai deixa de aceitar conexões antes de o kube-proxy tirá-lo dos endereços); com `preStop: sleep 8`, 3 restarts seguidos com 0 falhas.
- **Pontos a validar na AWS** (marcados como a verificar no código e no runbook): o formato do `overwrite:path` em integração privada (a doc não traz exemplo), a regra de saída do VPC Link até o NLB, as regras de segurança do NLB criado pelo controller e as permissões da `gha-eks-lab` (a experiência com a `gha-infra` mostrou que a policy de um pipeline novo costuma precisar de rodadas de correção de AccessDenied).
- **Memória dos nós**: `t4g.small` tem 2 GiB; controller, Argo CD core, CoreDNS, metrics-server, kube-proxy e a app dividem os 2 nós. O controller roda com 1 réplica por isso.
- **Efeito na stack principal**: as tags `kubernetes.io/role/internal-elb` nas subnets privadas são do lab; se a stack principal for aplicada com o lab no ar, o Terraform dela vai querer removê-las. O lab sempre é destruído antes.
- **Custo**: plano de controle em suporte padrão US$ 0,10/h; nós `t4g.small` ~US$ 0,0168/h cada (aproximado, tabela de FinOps); NLB e EBS dos nós **a verificar**; mais a stack principal no ar (~US$ 0,04/h). O total esperado fica perto dos ~US$ 0,17/h da steering só para o lab, mais a stack.

## Status

Aceito. Implementado e validado localmente e por `terraform validate`/`test`; **não aplicado na AWS**.
