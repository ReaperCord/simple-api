# Janela 3 de AWS: laboratório EKS

Data do desenho: 14/10/2026. Status: **executada em 14/10/2026, das 16:58 às 22:14** (resultado no fim). Horários em Brasília.

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

## Resultado (14/10/2026)

Dados brutos e lista de execuções: [`tests/k8s/2026-10-14-eks-janela-3-resultado.txt`](../../tests/k8s/2026-10-14-eks-janela-3-resultado.txt). Decisões e correções: [ADR 0014](../adr/0014-lab-eks-com-argo-cd-core-e-nlb-interno.md).

| # | Objetivo | Resultado |
|---|---|---|
| 1 | O lab sobe do zero pelo workflow | ✅ depois de 8 correções (3 de IAM, 5 de configuração), todas com causa medida |
| 2 | `/eks/connect` por IAM, sem segredo | ✅ 200, `app_connect` via Pod Identity |
| 3 | Mesmo API Gateway para `/` e `/eks` | ✅ `overwrite:path` e saída do VPC Link funcionam; `request_id` de `/eks` achado no log do pod |
| 4 | HPA, metrics-server, PDB, rolling update | ✅ HPA de 1 para 2 com CPU a 82%; rolling restart com tráfego: 0 em 596 e 1 em 788 falhas depois do readiness gate e do cross-zone (antes: 5,7% a 11%) |
| 5 | Argo CD sincroniza e se recupera | ✅ deriva no PDB desfeita em ~2 s; commits da `main` aplicados |
| 6 | RDS com dois clientes IAM | ✅ memória livre 49 a 67 MiB, swap 173 a 190 MiB, CPU até 7,2%, sem erro |
| 7 | `down` e destroy limpos | ✅ `down` sem resíduo; destroy da stack com 54 destroyed; `residual-check` com exit 1 só pelo atraso do índice de tags (10 regras de SG já `NotFound`) |

**Regra de parada:** o orçamento era 2 ciclos *sem progresso claro*. Foram 11 ciclos (fora o secret gravado errado), que resultaram nas 8 correções que ficaram. Dois partiram de hipótese errada e foram revertidos depois de medir: o retry do helm, para um erro que não era transitório, e o `preStop` de 90 s, que não era a causa. Um terceiro, o `createIngressClassResource=false`, contornou o sintoma antes de a causa (metrics-server) aparecer. Não houve ciclo sem progresso, mas o número passou muito do previsto.

**Fora do plano:** a AWS trocou o bundle de CAs do RDS (111 para 114 certificados, só entraram as 3 raízes da região sa-west-1). O `ADD --checksum` do Dockerfile barrou o build, como projetado; hash atualizado no PR #22 e imagem nova no ECS (task definition `:8`, `/connect` = 200).

**Custo estimado:** ~US$ 0,90 a 1,00 (~4,6 h de plano de controle, ~4 h de nós, ~2,7 h de NLB, ~5,2 h de stack), abaixo do teto de US$ 1,5. **A confirmar** no Cost Explorer (atraso de ~24 h).

**Lições:**
- O GC por `schedule` rodou uma vez em 5 h. O `down` manual é obrigatório.
- Para permissões de data sources, `TF_LOG=DEBUG` lista as chamadas reais e evita chute.
- `kubectl wait apiservice` não detecta o `/openapi/v2` corrompido.
