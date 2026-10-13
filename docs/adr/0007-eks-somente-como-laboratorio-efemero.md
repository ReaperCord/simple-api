# ADR 0007: EKS somente como laboratório efêmero

## Contexto

- O desafio vê ECS ou EKS como diferencial de serviço gerenciado. A trilha principal é ECS. [FATO: [`infrastructure/README.md`](../../infrastructure/README.md) linha 211]
- Preços do EKS em us-east-1: control plane a US$ 0,10/h em suporte padrão e US$ 0,60/h em suporte estendido. O lab EKS completo custa cerca de US$ 0,17/h. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seções "Preços de referência" e "Orçamento e estimativas", fonte aws.amazon.com/eks/pricing]
- Pods no Fargate só rodam em subnet privada, o que exigiria NAT. O node group gerenciado em subnet pública exige auto-assign de IPv4 público. O metrics-server não vem instalado. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Fatos de serviços AWS"]
- Regras do lab: root Terraform separado em `infrastructure/eks-lab/`, nós `t4g.small` on-demand no Free plan ou `t4g.medium` Spot no Paid plan, add-ons mínimos, mesma entrada pelo API Gateway, GitOps com Argo CD, vida máxima de 6 h e `destroy` seguido de `tools/residual-check.sh`. [FATO: [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) seção "Trilha EKS" e [`07-eks-lab.md`](../../.kiro/steering/07-eks-lab.md)]
- O plano da conta (Free ou Paid) decide o tipo de nó. A steering lista o plano como desconhecido. [FATO: lista "DESCONHECIDO" em [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md)]
- **Estado atual:** `infrastructure/eks-lab/`, `k8s/`, o workflow `eks-lab.yml` e a role `gha-eks-lab` não existem no repositório. [FATO: listagem do repositório em 13/10/2026; o `bootstrap` cria só `gha-plan`, `gha-deploy` e `gha-infra`, ver [`bootstrap/main.tf`](../../infrastructure/bootstrap/main.tf) linhas 73-90]

## Decisão

Tratar o EKS como laboratório efêmero e opcional, em root Terraform separado, ligado só em sessões curtas (no máximo 6 h), com `destroy` e varredura de resíduos ao final. A trilha ECS é a que fica ligada durante a avaliação.

## Alternativas consideradas

Cálculos com 730 horas por mês (convenção de cálculo):

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| EKS ligado 24x7 como trilha principal | Só o control plane: 0,10 × 730 = US$ 73,00/mês, acima do budget mensal de US$ 45, sem contar nós | Fora do orçamento |
| Suporte estendido do Kubernetes | US$ 0,60/h | Proibido pela steering |
| Fargate no EKS, EKS Auto Mode ou Karpenter | **A verificar** | Fargate exige NAT; os outros trazem complexidade e custo sem ganho para o desafio |
| Lab efêmero de até 6 h (escolhida) | ~US$ 0,17/h × 6 h = US$ 1,02 por sessão (cálculo sobre a estimativa da steering) | Escolhida |

## Consequências

- Os nós ficam em subnets públicas com IP público, pela mesma razão do [ADR 0005](0005-sem-nat-tasks-em-subnet-publica.md).
- O lab precisa de regra temporária no SG do RDS (5432 a partir do SG dos nós) e de rotas `ANY /eks` no mesmo API Gateway, sem tocar na stack principal além disso. Nenhuma dessas regras existe no código hoje.
- A tag `TTL` e um workflow agendado destroem clusters vencidos. O workflow ainda não existe.
- A decisão é de desenho. Nada do lab foi implementado nem validado, e o formato exato do `overwrite:path` com `$request.path.proxy` não foi testado.

## Status

Aceito como desenho. **Não implementado.** Decisão travada em [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md).
