---
inclusion: always
---

# Arquitetura decidida e restrições

Estas decisões estão TRAVADAS. Não proponha alternativas a menos que o Leandro peça, ou que um fato novo (com fonte) torne a decisão inviável — nesse caso, pare e explique antes de mudar qualquer coisa.

## Trilha principal (ECS) — ligada durante a avaliação

```
Internet ──HTTPS──> API Gateway HTTP API (estágio $default, throttling no estágio)
                      │ VPC Link V2 (SG próprio)
                      ▼
                 Cloud Map (private DNS namespace, registro SRV)
                      ▼
          ECS Fargate ARM64 0,5 vCPU / 1 GB, porta 3000, healthCheck em /health
          subnet PÚBLICA, assign_public_ip=true, SG aceita SÓ o SG do VPC Link
                      │ 5432, TLS obrigatório (verify-full)
                      ▼
          RDS PostgreSQL db.t4g.micro, single-AZ, subnet PRIVADA, sem IP público
```

Por que 0,5 vCPU: no benchmark local, 0,25 vCPU não cumpriu o SLO de `/connect` em nenhuma taxa (a 200 req/s o p99 foi 186 ms; a 400 req/s o p95 foi 57 ms — throttling de CPU) e saturou perto de 600 req/s; 0,5 vCPU cumpriu o SLO até 1.000 req/s (p50 0,8 / p95 18 / p99 53 ms). Fargate não aceita 0,5 vCPU com 512 MB: 1 GB é o mínimo. Revalidar na AWS.

Caminho no backend: em integrações privadas o API Gateway inclui o nome do estágio no caminho enviado ao backend. Use o estágio `$default` e, por segurança, `overwrite:path` = `$request.path` na integração do ECS — senão a app recebe `/<estágio>/connect` e responde 404.

## Módulos e arquivos do repo que NÃO entram na trilha principal

- `modules/network/nat-gateway` e a rota de `config/routes/private.json` → não instanciar. Subnets privadas (RDS) ficam só com a rota local.
- `modules/network/alb`, `target-group`, `listener` e `config/security_rules/rules-sg-alb.json` → sem uso (mantidos para uma eventual flag `ingress_mode = "alb"`, documentada como alternativa).
- A "arquitetura alvo" do `infrastructure/README.md` (ALB + NAT) é do autor do desafio; a nossa diverge de propósito e isso vai em ADR.
- Placeholder `${ALB_SG_ID}` em `rules-sg-ecs.json`: a origem real é o SG do VPC Link. Substituído por chaves simbólicas (`sg_refs: ["vpclink"]`), resolvidas pelo módulo `security-group` via mapa `sg_ids` (ver regra 9 de `04-terraform.md`); `templatefile()` com `${INGRESS_SG_ID}` não funciona porque o ID do SG é desconhecido no plan.

## Trilha EKS — laboratório efêmero

- Root Terraform separado: `infrastructure/eks-lab/`, lendo a stack principal via `terraform_remote_state`.
- Nós (managed node group, subnets públicas com auto-assign de IPv4 ligado):
  - Free plan: 2–3 × `t4g.small` on-demand (tipo elegível ao Free Tier).
  - Paid plan: 2 × `t4g.medium` Spot, com tipos diversificados.
  - Nunca Fargate no EKS (exige subnet privada → NAT).
- Add-ons: VPC CNI, CoreDNS, kube-proxy, EKS Pod Identity Agent, metrics-server (o HPA depende dele).
- Entrada: MESMO API Gateway. `ANY /eks/{proxy+}` e `ANY /eks` → VPC Link → NLB interno criado pelo AWS Load Balancer Controller, com `overwrite:path` a partir de `$request.path.proxy` para tirar o prefixo `/eks` (testar o formato exato).
- GitOps: Argo CD (componentes core) observando `k8s/overlays/eks` na branch `gitops` (ver `06-cicd.md`).
- Kubernetes em suporte padrão (US$ 0,10/h). Suporte estendido custa US$ 0,60/h — proibido.
- Vida máxima: 6 h por sessão. Destroy + `tools/residual-check.sh` ao final.

## Proibido sem pedido explícito

| Proibido | Motivo |
|---|---|
| NAT Gateway (trilha ECS e lab) | US$ 32,85/mês + tráfego |
| ALB na trilha ECS | custo fixo (~US$ 24/mês com IPv4); o desafio de ouro é API Gateway |
| RDS Multi-AZ, réplicas, Aurora | dobra/triplica custo; DR vem de PITR + snapshot |
| VPC interface endpoints | ~US$ 7,30/mês cada por AZ; mais caro que IPv4 público neste porte |
| Fargate no EKS, EKS Auto Mode, Karpenter | complexidade/custo sem ganho para o desafio |
| Usar `alb_controller_policy.json` em role de ECS | viola least privilege |
| Banco em container na AWS | o diferencial pedido é RDS |
| Criar pasta `terraform/` paralela a `infrastructure/` | o repo já tem a estrutura |
| Recursos fora de `us-east-1` (exceto documentação de DR) | custo e escopo (o tipo de cadastro da conta não proíbe outras regiões; não foi verificado se o Free plan as libera) |

## Portas e fluxo de rede

| De | Para | Porta | Regra |
|---|---|---|---|
| Internet | API Gateway | 443 | gerenciado pela AWS |
| SG do VPC Link | SG das tasks ECS | 3000/tcp | egress no SG do VPC Link + ingress nas tasks; única entrada das tasks |
| SG das tasks ECS | SG do RDS | 5432/tcp | egress das tasks + ingress do RDS |
| SG das tasks ECS | 0.0.0.0/0 | 443/tcp | pull do ECR, logs, Secrets Manager |
| SG do gerador k6 (temporário) | SG das tasks ECS | 3000/tcp | só durante testes de carga dentro da VPC; remover depois |
| SG dos nós EKS | SG do RDS | 5432/tcp | só durante o lab |

Nenhum SG aceita `0.0.0.0/0` de ENTRADA. VPC com `enable_dns_hostnames` e `enable_dns_support` = true (exigido pela zona privada do Cloud Map).

O registro no Cloud Map é SRV (exigido pela integração do API Gateway); o nome do serviço não resolve por registro A. Para testar de dentro da VPC, o gerador busca os IPs com `aws servicediscovery discover-instances` e distribui as requisições entre eles.

## Autoscaling

ECS Service Auto Scaling, target tracking `ECSServiceAverageCPUUtilization` = 60%, min 1, max 3, scale-out cooldown 60 s, scale-in 300 s. O alarme de scale-out precisa de alguns minutos de métrica acima do alvo e a task nova leva ~1 min para ficar saudável: conte com 3–5 min de reação. Roteamento acompanha via registro automático das tasks no Cloud Map (`service_registries` com `container_name`/`container_port`). Sem LB, o `healthCheck` do container é o único sinal de saúde.

## Conexões com o banco

A soma das conexões no PIOR momento (deploy com `maximumPercent=200` dobra as tasks; rolling update no EKS soma `maxSurge`) deve ficar ≤ 50% de `max_connections` do RDS (~80–110 no t4g.micro; confirmar com `SHOW max_connections;`). Com `DB_POOL_MAX=3` na AWS: ECS 3 tasks × 2 × 3 = 18 + EKS (3 + 1) × 3 = 12 → 30 conexões. O benchmark local usou pool 5; com 3 a folga por task segue grande (cada consulta leva ~1 ms), mas revalidar no teste de carga.

## DR

- RPO na mesma região: ≤ 5 min (backups automáticos + PITR, retenção 1 dia). RTO alvo 30–60 min (restore PITR + `terraform apply`), a MEDIR num teste real.
- Outra região/conta: a mesma stack parametrizada (região e AZs por variável, `data.aws_availability_zones`), com o state separado. O RPO entre regiões depende do que for copiado para lá: replicação de backups automáticos (PITR na outra região, RPO de minutos, custo de armazenamento e transferência) ou cópia diária de snapshot (RPO até 24 h). Compartilhar snapshot com outra conta exige chave KMS gerenciada pelo cliente (a chave padrão não pode ser compartilhada). Documentado, não implementado, por escopo e custo. O tipo de cadastro da conta não bloqueia recursos cross-região, e não foi verificado se o Free plan os libera.
