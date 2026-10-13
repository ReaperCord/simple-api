# Pacote de guardrails para o Kiro — KXC simple-api (v2, 12/10/2026)

Copie tudo para a raiz do seu fork do `simple-api`. Nada aqui altera código da aplicação ou da infraestrutura; são regras, agentes, uma spec, dados de benchmark e um script de verificação.

```
AGENTS.md                         # contrato anti-alucinação (lido por Kiro, Claude, Codex…)
.kiro/steering/                   # regras do projeto
  00-fonte-da-verdade.md          # always  — fatos verificados, IDs da auditoria, medições, o que é desconhecido
  01-arquitetura-e-restricoes.md  # always  — decisões travadas, módulos que não entram, portas, conexões, DR
  02-finops-guardrails.md         # always  — preços com fonte, budget, 5 perguntas antes de qualquer custo
  03-devsecops.md                 # fileMatch — segredos (com rotação), IAM por environment, container, scanners
  04-terraform.md                 # fileMatch infrastructure/** — padrões e comandos permitidos/proibidos
  05-aplicacao.md                 # fileMatch application/** — contrato da API e correções A2–A12
  06-cicd.md                      # fileMatch .github/** — OIDC, ordem do primeiro deploy, branch gitops
  07-eks-lab.md                   # fileMatch k8s/**, eks-lab/** — lab efêmero, nós por plano da conta, GitOps
  08-testes-de-carga.md           # fileMatch tests/load/** — perfis, onde cada um roda, SLOs, estimativas
.kiro/agents/*.json               # 7 agentes com permissões por escopo
.kiro/prompts/*.md                # prompt de cada agente + _base.md comum
.kiro/specs/01-app-hardening/     # primeira spec (requisitos EARS, design, tarefas)
tests/load/results/               # baseline LOCAL (CSV) + saída bruta da primeira rodada
tests/load/local-baseline/        # script k6, driver e método do baseline
tools/residual-check.sh           # varredura somente-leitura de resíduos após destroy
```

## O que mudou da v1 para a v2

- **Fonte da verdade:** a v1 dizia "se o repo divergir, o repo vence" — isso faria o Kiro seguir o README original (ALB + NAT). Agora fatos do código e decisões de arquitetura têm regras separadas.
- **Conta AWS:** regras do Free plan × Paid plan; tipo de nó do EKS depende do plano. Conta aberta pelo cadastro novo da AWS ("Sign up for AWS (new)") não tem recursos cross-região nem GuardDuty sem ativar os recursos avançados, nos dois planos.
- **Números:** benchmark refeito (aquecimento, 3 séries, log, todas as threads sob a cota); task de 0,5 vCPU / 1 GB; p50/p95/p99 avaliados contra o SLO completo.
- **Segurança:** rotação de 7 dias do segredo do RDS tratada; exceções de `Resource: "*"` (incluindo `ecs:DescribeTaskDefinition`); um GitHub environment por workflow (senão o deploy e o workflow agendado do EKS teriam o mesmo `sub` OIDC), cada um só na `main` e com aprovação só no `infra` (no `eks-lab` ela travaria o destroy agendado); `.tflock` com Get/Put/Delete para o `plan`.
- **Arquitetura:** estágio `$default` + `overwrite:path` (em integração privada o nome do estágio vai no caminho do backend); conexões contando o surge de deploy (`DB_POOL_MAX=3` na AWS); ECR no bootstrap e primeira imagem antes da stack; branch `gitops` para o Argo CD (a `main` protegida rejeitaria o push).
- **FinOps:** budget de US$ 45 com créditos EXCLUÍDOS (no Terraform `include_credit` vem `true`, e aí nenhum alerta dispara) e sem depender de previsão (precisa de ~5 semanas de histórico).
- **Testes de carga:** stress/breakpoint/soak dentro da VPC com alvos de `discover-instances` (o registro é SRV e o k6 não resolve SRV); spike pelo API Gateway com o throttling elevado e 10 min de duração (o autoscaling leva 3–5 min).
- **Permissões dos agentes:** ajustadas à semântica documentada do Kiro (abaixo); leitura de `.env`, tfstate, chaves e caches de credencial bloqueada também para a ferramenta de leitura de arquivos.
- **residual-check.sh:** 0 = limpo, 1 = há resíduos, 2 = a consulta falhou; ignora o que tem `Track=bootstrap`; cobre instâncias EC2, ENIs, VPC Links, Cloud Map, zonas do Route 53, alarmes e GuardDuty (se o GuardDuty não existir na conta, vira AVISO, não erro). Testado com uma AWS CLI simulada (limpo, com resíduo, consulta negada, sem credencial, GuardDuty indisponível) e com shellcheck.

## Como o Kiro avalia as permissões (doc oficial)

- `deny` > `ask` > `allow`: vence o efeito mais restritivo que casar, em qualquer escopo. Por isso nenhuma regra `ask` deste pacote casa com algo que está no `allow` do mesmo agente.
- Comandos compostos (`;`, `&&`, `||`, `|`) são divididos e cada parte é avaliada sozinha. Ex.: em `curl … | sh`, a parte `sh` não casa com nenhum `allow` e cai no padrão (pedir aprovação).
- Em shell, `*` casa qualquer sequência; em caminhos, `*` fica num componente e `**` atravessa pastas.
- O que não casa com nenhuma regra pede aprovação. Leitura de arquivos do workspace é liberada por padrão — daí os `deny` de `fs_read`.

## Os agentes

| Agente | Escreve em | Pede confirmação para (além do que não estiver liberado) |
|---|---|---|
| `kxc-arquiteto` | `docs/**`, `README.md`, `.kiro/specs/**` | — |
| `kxc-app` | `application/**`, Compose, `.dockerignore`, tarefas da spec | `npx`, `npm audit fix`, `docker run/push/login` |
| `kxc-iac` | `infrastructure/**` (exceto `eks-lab/`) | `terraform apply/destroy/import`, `terraform state list/show` |
| `kxc-devsecops` | `.github/**`, configs de scanners, `modules/security/**`, `bootstrap/**` | — |
| `kxc-perf` | `tests/load/**`, `docs/performance/**` | `k6 run` |
| `kxc-eks` | `k8s/**`, `infrastructure/eks-lab/**` | `helm install/upgrade/uninstall`, apply/destroy, `argocd` |
| `kxc-verificador` | `docs/verificacoes/**` | — (só audita) |

Para todos: `git commit/push/restore/rebase` pedem confirmação. Bloqueado (`deny`): `rm -rf`/`rm -r`, `sudo`, `git push --force`, `git reset --hard`, `git clean -f`, `find -delete/-exec`, `-auto-approve`, `terraform state rm|mv|pull|push`, `terraform console`, `terraform output -json|-raw`, `terraform show -json`, `aws … delete-*/terminate-*`, `aws s3 rm|rb`, criar access key/usuário IAM, ler segredos e credenciais por qualquer caminho (`get-secret-value`, `--with-decryption`, `get-login-password`, `assume-role`, `get-role-credentials`, `~/.aws/sso`, `~/.aws/cli/cache`, `~/.aws/credentials`, variáveis de ambiente), `gh api` com escrita; ler ou escrever `*.tfstate`, `.env*` (exceto `.env.example`), chaves e `~/.aws`; escrever em `.kiro/steering/**`, `.kiro/agents/**`, `.kiro/prompts/**` e `AGENTS.md`.

## Configuração recomendada

1. Copie o pacote para a raiz do fork e faça commit.
2. **Perfil AWS somente leitura para o Kiro** (ex.: `kxc-readonly`, uma role com `ReadOnlyAccess`). No terminal onde o Kiro roda: `export AWS_PROFILE=kxc-readonly`. Com esse perfil, `terraform plan` precisa de `-lock=false`.
3. Para um `apply`, você troca o perfil naquele momento e aprova o comando — ou usa o workflow `infra.yml` com aprovação.
4. Se quiser isolamento de verdade, rode o Kiro num devcontainer sem credenciais de escrita montadas.

## Fluxo recomendado

1. Confirme o plano da conta (Billing → Free Tier) e se ela foi aberta pelo cadastro novo, e anote em `00-fonte-da-verdade.md` (só você edita a steering).
2. Abra a spec `01-app-hardening` com o `kxc-app` e execute as tarefas na ordem.
3. Ao fim de cada fase, rode o `kxc-verificador` sobre o diff e o relatório.
4. Para a infra, peça ao `kxc-arquiteto` a decomposição e passe as tarefas ao `kxc-iac`.
5. Depois de qualquer `destroy`: `bash tools/residual-check.sh` (código 2 = consulta falhou, não é "limpo").

## Limites que você precisa conhecer

- Permissões por padrão de comando NÃO são sandbox: um interpretador (`node -e`, `python3`) pode fazer qualquer coisa. Por isso eles pedem confirmação, e a garantia real vem do perfil AWS somente leitura e da revisão do diff.
- Testei as regras com uma simulação em Python da semântica documentada (20 casos, incluindo `aws --region … secretsmanager get-secret-value`, `cd x && terraform state rm`, `curl | sh` e `gh api -X POST`). Confira no seu Kiro com um comando inofensivo bloqueado (ex.: `git reset --hard` num repo de teste).
- Formato dos agentes conforme a doc atual (`tools` + `permissions.rules` com `capability`, `match`, `exclude`, `effect`). Se sua versão do Kiro CLI reclamar do formato, use `/upgrade-agent`.
- Agentes customizados NÃO carregam a steering sozinhos; por isso cada JSON tem `"resources": ["file://.kiro/steering/**/*.md", ...]`.
- O hook `PostToolUse` do `kxc-iac` (só roda `terraform fmt`) usa um matcher por nome de ferramenta; se não disparar na sua versão, ele é opcional.
- Não fixei `model` nos agentes: escolha no `/model`.
- Kiro IDE: a steering e o `AGENTS.md` funcionam direto; os agentes JSON são do Kiro CLI/agentes customizados.

## Mantenha atualizado

Quando um fato mudar (plano da conta, crédito, prazo, medição na AWS), edite `00-fonte-da-verdade.md` VOCÊ MESMO. Os agentes estão proibidos de editar a steering justamente para não "reescreverem a verdade".
