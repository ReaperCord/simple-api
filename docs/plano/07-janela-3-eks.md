# Janela 3 de AWS: laboratório EKS

Data do desenho: 14/10/2026. Status: **desenho, aguardando OK do Leandro** (apply, destroy, recursos novos, secrets e environment no GitHub). Horários em Brasília.

## O que a janela valida

| # | Objetivo | Como |
|---|---|---|
| 1 | O lab sobe do zero pelo workflow `eks-lab.yml` (role `gha-eks-lab`, Terraform etapas 1 e 2, controller, Argo CD core) | `gh workflow run eks-lab.yml -f action=up -f image_tag=<SHA>`; corrigir `AccessDenied` e o que mais aparecer, em ciclos (cada ciclo: ler o erro, corrigir com comentário, PR, merge, reexecutar) |
| 2 | A app no EKS conecta ao RDS por IAM (Pod Identity), sem segredo no cluster | `GET /eks/connect` = 200 pelo API Gateway |
| 3 | O mesmo API Gateway serve `/` (ECS) e `/eks` (EKS) | `/eks/health`, `/eks/connect` e `/`, `/health`, `/connect`; **formato do `overwrite:path`** e a **saída do VPC Link até o NLB** (os dois pontos que a doc não cobre) |
| 4 | HPA, metrics-server (add-on), PDB e rolling update no EKS | `kubectl top`, carga de um pod temporário até o HPA escalar, restart do Deployment com requisições em curso |
| 5 | Argo CD sincroniza e se recupera | `Application` Synced e Healthy; apagar um pod e ver a recuperação |
| 6 | O RDS aguenta dois clientes (ECS e EKS) com IAM | `FreeableMemory`, `SwapUsage` e `DatabaseConnections` (o risco do ADR 0013) |
| 7 | `down` e o destroy agendado deixam tudo limpo | `eks-lab.yml action=down`, `terraform destroy`, NLB e SG removidos, `tools/residual-check.sh` |

## Sequência

**Etapa A (custo zero, antes de gastar):**
1. Reabilitar o workflow `eks-lab.yml` (hoje desabilitado para não rodar o agendamento sem o secret).
2. Aplicar o bootstrap com a role `gha-eks-lab` (plano de 5 recursos de IAM, já feito e medido: policies de 1.645 e 2.793 caracteres).
3. GitHub: environment `eks-lab` (só a branch `main`, sem aprovação), secret `AWS_EKS_LAB_ROLE_ARN` e o secret `EKS_LAB_ADMIN_ARNS` (o ARN do usuário `kxc-admin`, para eu operar o cluster).

**Etapa B (começa o custo):**
4. `infra.yml apply` da stack principal com a imagem `e1673a47…` (a que tem o pré-aquecimento); você aprova o gate. `tools/run-db-init.sh`, `/connect` = 200, atualizar `API_URL`.
5. `eks-lab.yml action=up` com a mesma tag; validações 1 a 6; `eks-lab.yml action=down`; `infra.yml destroy`; `residual-check`.

Regra de parada: se o lab não subir depois de **2 ciclos de correção** sem progresso claro, eu paro, faço `down` e destroy, e registro o resultado. O agendamento horário por TTL (6 h) é a rede de segurança contra o lab esquecido, não o plano.

## FinOps (5 itens)

1. **O que muda:** a stack principal (54 recursos) e o lab (cluster EKS, node group de 2 `t4g.small`, 5 add-ons, 2 roles de Pod Identity, regras de SG, tags de subnet, rotas `/eks`, NLB interno criado pelo controller). Fora do Terraform: nada além do que os workflows criam (controller, Argo CD, Application, ConfigMap).
2. **Custo por hora** (tabela de `02-finops-guardrails.md` e fonte oficial quando há):

| Recurso | US$/h | Fonte |
|---|---|---|
| Stack principal (API ECS, RDS, IPv4) | ~0,041 | medido na janela 1 |
| EKS, plano de controle em suporte padrão | 0,10 | tabela de FinOps |
| 2 nós `t4g.small` on-demand | ~0,034 (2 × ~0,0168) | tabela de FinOps (aproximado) |
| 2 IPv4 públicos dos nós | 0,010 | tabela de FinOps |
| NLB interno | 0,0225 + 0,006 por LCU-hora | https://aws.amazon.com/elasticloadbalancing/pricing/ (aberta em 14/10/2026) |
| 2 volumes gp3 de 20 GB dos nós | ~0,004 | **a verificar** (a página do EBS não confirma o preço de us-east-1; usei o exemplo de US$ 0,08/GB-mês como hipótese) |
| **Total** | **~0,22 por hora** (~0,25 com as requisições e o LCU) | |

   Correção: antes eu tinha falado em ~US$ 0,35/h; o cálculo detalhado dá ~US$ 0,22/h.
   **Estimativa:** ~3 h × US$ 0,25 ≈ **US$ 0,75**; **teto** (dobro: ciclos extras de correção e até 6 h no ar) ≈ **US$ 1,5**. Saldo de crédito: US$ 138,52.
3. **Depois do destroy:** nada deve ficar (NLB, target groups e SG do NLB saem pelo controller no `down`; ENIs do cluster saem com o cluster; as roles do lab e as regras de SG saem no destroy). Task definitions `ACTIVE` por `skip_destroy` não cobram. Confirmar com `tools/residual-check.sh` e, se sobrar ENI ou NLB órfão, apagar pelo CLI.
4. **Tempo ligado:** ~3 h, no máximo 6 h (TTL).
5. **Free plan:** **DESCONHECIDO** se o plano aceita criar EKS e o node group; a lista de serviços do Free plan desta conta nunca foi verificada, e o RDS já mostrou uma restrição (retenção de backup). `t4g.small` é elegível ao Free Tier. Se o EKS for recusado, o apply falha no cluster, nada mais cobra e registro o erro como resultado.

## Riscos

- **IAM da `gha-eks-lab`:** policy nova nunca exercitada; a `gha-infra` precisou de várias rodadas. É o motivo do orçamento de 2 ciclos.
- **Memória:** nós de 2 GiB com controller, Argo CD core, CoreDNS, metrics-server e a app; o RDS (`db.t4g.micro` com IAM) agora com dois clientes.
- **Orphans:** se o NLB ou o SG dele ficarem para trás, bloqueiam o destroy da VPC. O `down` apaga o Service e espera o NLB sumir antes do Terraform.
- **Endpoint público do cluster** (`0.0.0.0/0`, acesso só por IAM): registrado no `.trivyignore` com justificativa; vida de até 6 h.
- **Mudanças fora do Terraform:** só as tags de subnet que o lab cria; o lab sempre é destruído antes de a stack principal.
