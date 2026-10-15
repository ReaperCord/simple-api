# ADR 0014: laboratório EKS efêmero (Argo CD core, NLB interno pelo mesmo API Gateway)

Complementa o [ADR 0007](0007-eks-somente-como-laboratorio-efemero.md) (EKS só como lab efêmero) com as decisões de implementação.

## Contexto

- A trilha ECS é a principal. O EKS entra como diferencial, num root Terraform separado (`infrastructure/eks-lab`), com vida máxima de 6 h, e **nunca altera** a stack principal. [FATO: [`07-eks-lab.md`](../../.kiro/steering/07-eks-lab.md), [ADR 0008](0008-terraform-com-roots-separados.md)]
- Versões do Kubernetes em **suporte padrão** em 14/10/2026: 1.34 a 1.37, padrão 1.36 (fim do suporte padrão em 01/08/2027). A 1.33 e as anteriores já estão em suporte estendido (US$ 0,60/h, proibido). [FATO: `aws eks describe-cluster-versions`, 14/10/2026]
- Add-ons do EKS disponíveis para a 1.36: VPC CNI v1.23.2, CoreDNS v1.14.7, kube-proxy v1.36.0, Pod Identity Agent v1.4.0 e metrics-server v0.7.2, v0.8.0, v0.8.1 e v0.9.0 (o HPA depende dele). [FATO: `aws eks describe-addon-versions`, 14/10/2026] **O lab usa a v0.8.1**: a v0.9.0 corrompe o `/openapi/v2` agregado (ver Consequências). [FATO: medido na janela 3; https://github.com/kubernetes-sigs/metrics-server/issues/1868]
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

- **Validado localmente (kind) e em CI.** Teste local com Kubernetes 1.35: contrato HTTP, uid 1000, FS somente leitura, Pod Security `restricted` barrando pod privilegiado, HPA com metrics-server v0.9.0 e escala sob carga, PDB e rolling update sem falhas. Esse teste **encontrou uma falha real**: sem `preStop`, 1 requisição em 358 falhou num rolling restart (o pod que sai deixa de aceitar conexões antes de o kube-proxy tirá-lo dos endereços); com `preStop: sleep 8`, 3 restarts seguidos com 0 falhas.
- **Aplicado na AWS na janela 3 (14/10/2026)**, dados em [`tests/k8s/2026-10-14-eks-janela-3-resultado.txt`](../../tests/k8s/2026-10-14-eks-janela-3-resultado.txt). Validado: o lab sobe e desce pelo workflow; `/eks/connect` = 200 com IAM via Pod Identity (sem segredo no cluster); o mesmo API Gateway serve `/` (ECS) e `/eks` (EKS) e o `overwrite:path` funciona; o Argo CD aplica os commits da `main` e desfaz deriva; o HPA escala com CPU; o RDS aguenta os dois clientes IAM; o `down` e o destroy não deixam resíduo. Precisou de **8 correções**, todas com causa medida:
  1. `gha-eks-lab`: `iam:GetRole` nas roles de serviço do EKS, **também pelo ARN sem path** (para role ainda inexistente o IAM avalia `role/<nome>`, confirmado no simulador).
  2. `gha-eks-lab`: `iam:PassRole` para `pods.eks.amazonaws.com` (Pod Identity).
  3. `gha-eks-lab`: `elasticloadbalancing:DescribeLoadBalancerAttributes` (o `data.aws_lb` chama; medido no log de debug do provider 6.68.0).
  4. **metrics-server v0.9.0 → v0.8.1.** A v0.9.0 vaza `ArbitraryKeys`/`SchemaProps` no `/openapi/v2` agregado (131 ocorrências) e o v2 em protobuf passa a responder **503**; os APIServices continuam `Available`. Isso quebra a validação de `kind: List` (helm e kubectl) e o cache de cluster do Argo CD, com a mesma mensagem: "the server is currently unable to handle the request". Um teste do Terraform impede voltar para v0.9.x.
  5. Chart do controller com `createIngressClassResource=false` (o único `kind: List` do caminho; o lab não usa Ingress). Aplicado antes de achar a causa 4; ficou por não ser necessário.
  6. **AppProject próprio** para o Argo CD core: sem `argocd-server` ninguém cria o projeto `default`. O projeto só aceita este repositório, só o namespace `simple-api` e, de recurso de cluster, só `Namespace`.
  7. **Pod readiness gate** do controller (label no namespace do overlay EKS): o pod novo só fica `Ready` quando está healthy no target group.
  8. **Cross-zone no NLB** (anotação do Service): desligado por padrão, fazia o nó do NLB da AZ antiga ficar sem alvo quando o pod trocava de AZ. Medido: no rolling restart com tráfego, de 5,7% a 11% de falhas no total em 4 medições (cerca de metade dentro da janela de troca, que durava ~65 a 100 s) para **0 em 596 e 1 em 788**. Um `preStop` de 90 s foi tentado antes e **não** resolveu (35 em 676, com o pod antigo ainda vivo); foi revertido.
- **Janela curta de 15/10/2026 (10:10 a ~11:50 de Brasília)**, para os três itens abertos da janela 3:
  - **GC.** O `schedule` do GitHub rodou **3 vezes em ~17 h** de cron horário. Por isso todo `up` agora dispara um **vigia** (`eks-lab-watchdog.yml`), que dorme até o TTL e chama `eks-lab.yml action=gc`. O cron fica como segunda rede, e o TTL vai de 1 a 5 h, por causa do limite de 6 h por job. **Validado:** `up` com `ttl_hours=1`. Com o TTL em 11:25:58, o vigia disparou o `gc` às 11:28:01, e o `gc` destruiu o lab sozinho (32 recursos) até 11:35:57, sem resíduo.
  - **Smoke.** Num `up` real, o smoke de 120 s falhou com 404, depois 500 e depois 503. O NLB recém-criado (10:38:21) só passou a responder de forma estável pelo VPC Link às 10:42:20, ~4 min depois. O prazo passou a 6 min.
  - **Falha de 1 em 788.** Medida com linha do tempo em 5 restarts: **8 falhas em 2.638 requisições (0,30%), todas na janela do SIGTERM do pod antigo** (o SIGTERM chegou em +50,1 s e +50,7 s, e as falhas caíram de ~+49 s a +55 s). Os dados estão em [`tests/k8s/2026-10-15-eks-rolling-restart-keepalive.txt`](../../tests/k8s/2026-10-15-eks-rolling-restart-keepalive.txt). Dois tipos:
    - **503 do API Gateway**, no SIGTERM: a app fecha as conexões keep-alive enquanto o VPC Link envia uma requisição por elas.
    - **Timeout de 5 s**, logo depois: o VPC Link reaproveita uma conexão presa ao alvo `draining`, que o NLB mantém por até 300 s, depois que o pod já morreu.

    **Tarde de 15/10 (correção medida;** dados em [`tests/k8s/2026-10-15-eks-drenagem-e-prestop40.txt`](../../tests/k8s/2026-10-15-eks-drenagem-e-prestop40.txt)**):**
    - **Drenagem com `sleep 8`.** No SIGUSR2 a app passa a responder com `Connection: close` (`src/drain.js`, imagem `820175a`), e o `preStop` é `kill -USR2 1; sleep 8`. **Não resolveu:** 8 falhas em 2.853 (0,28%). O log confirma a drenagem 8 s antes do SIGTERM.
    - **Causa real.** As conexões novas abertas por causa do `Connection: close` ainda chegavam ao pod antigo. Então **o NLB continua mandando fluxos novos ao alvo `draining` por mais de 8 s** depois da desregistração.
    - **`preStop` de 40 s com grace de 60 s,** só no overlay do EKS, pelo GitOps (`043fa23`): **0 falhas em 2.081**. Na taxa anterior, seriam esperadas ~6.
    - **Mantido:** a drenagem fica, porque não piorou nada, mas não provou ganho próprio. O kind continua com 8 s.
  - **Dashboard do Argo CD.** `argocd admin dashboard -n argocd` roda a interface na máquina do operador, com o acesso dele ao cluster. Nada é instalado no cluster e nada fica exposto. Testado em 15/10, com o CLI v3.5.5 conferido pelo checksum do release.
  - **Taxonomia de tags (15/10).** `Component` em todos os recursos do lab, labels `project`, `track` e `component` nos objetos do Kubernetes, e as mesmas tags no NLB por anotação. Conferido na AWS.
  - **Achados novos, a corrigir.**
    - Um apply da stack principal com o lab no ar remove as tags `kubernetes.io/role/internal-elb` das subnets privadas; o `up` as recria. A correção é um `ignore_tags` com o prefixo `kubernetes.io/` no provider da stack.
    - Repetir o `up` com o lab no ar faz a etapa 1 destruir as rotas `/eks`, que a etapa 2 recria segundos depois. A correção é manter `enable_api_route` na etapa 1 quando o lab já existe.
- **Memória dos nós**: `t4g.small` tem 2 GiB; controller, Argo CD core, CoreDNS, metrics-server, kube-proxy e a app dividem os 2 nós. O controller roda com 1 réplica por isso.
- **Efeito na stack principal**: as tags `kubernetes.io/role/internal-elb` nas subnets privadas são do lab; se a stack principal for aplicada com o lab no ar, o Terraform dela vai querer removê-las. O lab sempre é destruído antes.
- **Memória medida**: os nós ficaram em 49% e 65% de memória com tudo no ar (`kubectl top nodes`).
- **Custo**: plano de controle em suporte padrão US$ 0,10/h; nós `t4g.small` ~US$ 0,0168/h cada (aproximado, tabela de FinOps); NLB US$ 0,0225/h mais LCU; mais a stack principal no ar (~US$ 0,04/h). Real da janela 3, pelo Cost Explorer: **US$ 0,52** nas linhas exclusivas do lab (4,43 h de plano de controle, 3 h de NLB) e ~US$ 0,75 a 0,80 com a stack principal. Os nós `t4g.small` foram **cobertos pelo Free Tier** (7,9 h a US$ 0). Ver [`05-custo-real.md`](../plano/05-custo-real.md).

## Status

Aceito. Implementado, validado localmente e **aplicado e validado na AWS em 14/10/2026** (janela 3), com as 8 correções acima.
