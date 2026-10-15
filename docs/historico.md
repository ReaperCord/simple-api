# Histórico de execução

Registro detalhado, janela por janela, do que foi verificado na AWS, do que falhou e de como foi corrigido. Era a seção "Pendências" do README até 15/10/2026; foi movido para cá sem cortes quando o README passou a seguir a estrutura do desafio. Os horários estão em Brasília.

Resultados consolidados: [`README.md`](../README.md). Relatórios de verificação: [`docs/verificacoes/`](verificacoes/).

## Diário das janelas (13 a 15/10/2026)

Estado em 14/10/2026 (fim da janela 3): a stack foi criada na AWS três vezes (13/10 e duas vezes em 14/10), testada e **destruída** em todas (o bootstrap permanece). Na janela 3 o laboratório EKS foi aplicado e validado ([ADR 0014](docs/adr/0014-lab-eks-com-argo-cd-core-e-nlb-interno.md), [`docs/plano/07-janela-3-eks.md`](docs/plano/07-janela-3-eks.md)). Resultados em [`docs/performance/benchmark-aws.md`](docs/performance/benchmark-aws.md) e no plano de execução em [`docs/plano/`](docs/plano/00-plano-execucao.md)). Abaixo, o que foi verificado e o que continua sem verificação.

**Verificado na AWS**
- Bootstrap aplicado (state local, nunca versionado): bucket de state, ECR, budget, provedor OIDC, roles `gha-plan`, `gha-deploy` e `gha-infra` e o Resource Group `kxc-simple-api-RG` (por tag `Project`). GitHub configurado: environments `deploy` e `infra` (com aprovação) e variáveis do repositório.
- Apply da stack pelo `infra.yml` em duas rodadas (plan de 50 recursos). A primeira falhou parcialmente por permissões da `gha-infra` (`ecr:DescribeImages`, `apigateway:TagResource`, `route53:CreateHostedZone` e leituras do Route 53, `rds:ListTagsForResource`); cada falta foi corrigida em `modules/oidc/main.tf` com o motivo em comentário (least privilege iterativo) e o bootstrap reaplicado. A segunda rodada concluiu (17 recursos criados, sem novo AccessDenied).
- O Free plan desta conta recusa `backup_retention_period = 7` (`FreeTierRestrictionError`): o `dev` usa 1, ou seja, **PITR de 1 dia** (o alvo documentado é 7).
- Pelo API Gateway, `GET /`, `/health` e `/connect` respondem 200. O RDS é PostgreSQL 16.13 e o `max_connections` do `db.t4g.micro` é 79 (medido). O TLS `verify-full` e a leitura do segredo gerenciado pelo RDS funcionam (o `/connect` conecta). A imagem arm64 roda no Fargate.
- `deploy.yml` de ponta a ponta: build multi-arch, Trivy nos dois digests, SBOM, deploy por digest no ECS e smoke do pipeline (run 38461659742).
- **Laboratório EKS (janela 3, 14/10):**
  - O lab sobe e desce pelo `eks-lab.yml`.
  - `/eks/connect` responde 200 por IAM via Pod Identity, sem segredo no cluster, no mesmo API Gateway do ECS.
  - O Argo CD core aplica a `main` e desfaz deriva, e o HPA escala com CPU.
  - Rolling restart com tráfego: 0 falhas em 596 e 1 em 788.
  - O RDS aguentou os dois clientes IAM.
  - Foram 8 correções, com destaque para:
    - o metrics-server v0.9.0 corrompia o `/openapi/v2`;
    - o NLB precisou de cross-zone e de readiness gate;
    - a `gha-eks-lab` precisou de três permissões a mais.
  - Dados em [`tests/k8s/2026-10-14-eks-janela-3-resultado.txt`](tests/k8s/2026-10-14-eks-janela-3-resultado.txt).
  - Destroy às 22:14 de Brasília (run 38664023276, 54 destroyed). O `residual-check` saiu com exit 1 só pelo atraso do índice de tags: as 10 regras de SG listadas já estavam `NotFound`.
- **Janela curta do lab EKS (15/10, 10:10 a ~11:50):**
  - **Vigia do TTL validado:** o lab foi destruído sozinho pelo `gc` 2 min depois do TTL. O cron do GitHub, que deveria ser horário, rodou só 3 vezes em ~17 h, e agora é só a segunda rede.
  - **Smoke:** o prazo passou a 6 min, porque um NLB recém-criado levou ~4 min para responder.
  - **Falhas no rolling restart:** a causa ficou medida em 0,30%, no SIGTERM do pod antigo, por uma corrida de keep-alive. A correção está proposta no [ADR 0014](docs/adr/0014-lab-eks-com-argo-cd-core-e-nlb-interno.md) e ainda não foi implementada.
- Carga na AWS, rotulada AWS e separada da LOCAL: pelo API Gateway (smoke e baseline a 40 req/s) e dentro da VPC (load até 500, stress até 1.000 e rampa até 1.500 req/s, sem erro; o breakpoint não foi atingido). Detalhes, ressalvas e dados em `tests/load/results/`.

**Ainda não verificado**
- (Resolvido em 14 e 15/10) **Custo real das três janelas**, todo coberto por crédito:
  - 13/10: US$ 1,48 bruto;
  - 14/10: US$ 1,28, com as janelas 2 e 3;
  - 15/10 até 09:35: US$ 0,21 (parcial).

  A janela 3 custou ~US$ 0,75 a 0,80 contra US$ 0,90 a 1,00 estimados, porque os nós do EKS saíram de graça pelo Free Tier. O saldo de crédito está em **US$ 157,03**; subiu ~US$ 20 por um crédito extra do Free plan, cujo motivo não foi conferido.
- Janela 1 em 13/10: o Cloud Map cobra por chamada de API, mas foram ~1 chamada por 15 requisições do API Gateway (+6,8% sobre o custo do API Gateway), não uma por requisição; o mecanismo (cache) não foi verificado. Ver [`docs/plano/05-custo-real.md`](docs/plano/05-custo-real.md).
- Autoscaling: medido em um spike (100 → 1.500 req/s pelo API Gateway): decisão de scale-out ~5 min depois do salto, task nova rodando ~44 s depois da decisão, 3 tasks em ~8,7 min e volta a 1 task ~22 min depois do fim do spike. Uma execução só; durante a saturação o p95 chegou a 290 ms e o erro a 0,17% num minuto ([`docs/autoscaling.md`](docs/autoscaling.md), [`docs/performance/benchmark-aws.md`](docs/performance/benchmark-aws.md)).
- Throttling de CPU do Fargate não medido. Soak de 2 h (600 req/s, 0% de erro, sem deriva) e 3 séries por perfil (task nova da API em cada) foram feitos em 14/10; a variação entre tasks foi grande (CPU a 500 req/s: 33%, 42% e 56%), então uma série não vale como capacidade ([`docs/performance/benchmark-aws.md`](docs/performance/benchmark-aws.md)). O spike foi feito com o throttling do estágio elevado temporariamente (restaurado em 50/100).
- Rotação de 7 dias do segredo: a app invalida o cache em `28P01` (testado com cliente falso), mas uma rotação real não foi exercitada.
- Conectividade das tasks até ECR, CloudWatch Logs e Secrets Manager por IP público, sem NAT nem endpoints: funcionou nos testes, sem análise de falhas.
- **Destroy executado** pelo `infra.yml` (run 38486943440: 0 to add, 0 to change, 50 to destroy; gate `infra` aprovado). Conferência com `tools/residual-check.sh`: na noite do destroy o script saiu com **exit 1**, porque a seção por tag listava itens já removidos (índice de tags com atraso: as 7 regras de SG e o service sumiram do índice em ~12 h) e artefatos de ECS que a AWS nunca remove (cluster `INACTIVE` e task definitions). Em 14/10 o script passou a **classificar o ECS pelo status real** (cluster ou service ativo, ou não classificável, é resíduo; `INACTIVE` é ignorado; task definition `ACTIVE` só é informada), com teste em `tools/test-residual-check.sh` (12 casos, validado por teste de mutação), e a varredura saiu com **exit 0** (só o aviso esperado do GuardDuty). As task definitions `simple-api-dev:1` e `:2` ficam `ACTIVE` por `skip_destroy = true` (sem custo). **Janela 2 (14/10):** destroy em 15:43 de Brasília (run 38614733505, 54 destroyed); o script saiu de novo com **exit 1**, desta vez só por 7 regras de SG que o índice de tags ainda listava e que a API EC2 já não encontra (`NotFound`, conferido uma a uma); não há VPC, SG, RDS nem cluster ativo do projeto, e a seção de ECS foi classificada corretamente. O exit 0 depende de o índice de tags atualizar (na janela 1 levou menos de ~12 h). **15/10, 09:32:** depois da janela 3 e do teste do `infra.yml`, o script saiu com **exit 0** (só o aviso do GuardDuty), menos de ~9,5 h depois do último destroy.

**Build, testes e CI**
- Build `linux/arm64` verificado no CI (PR #1) e no `deploy.yml`. O build arm64 local não é possível (o builder do Docker Desktop não tem QEMU). Não foi verificado se `TRIVY_PLATFORM` chega ao scan arm64 do `deploy.yml`.
- Os testes da app citados vêm da última execução registrada (48 testes: 44 passam, 4 de integração ignorados, 0 falham).
- O `ci.yml` só roda em `pull_request`. Desde 14/10 toda mudança passa por um PR de validação no fork, fechado sem merge, antes do merge local na `main`. Os PRs #13 a #22 ficaram todos verdes, exceto o `dockerfile` dos PRs #18 a #21, que falhou pela troca do bundle de CAs do RDS (corrigida no #22). O teste do módulo `oidc` foi corrigido, e o `plan` do CI passa.

**Desempenho**
- O benchmark local não foi repetido com a imagem final (`--cpus=0.5`, `DB_POOL_MAX=3`) e a compatibilidade do `load.js` local com k6 2.x não foi conferida. Números LOCAIS e AWS não se misturam.

**Segurança**
- A API é pública e sem autenticação (contrato do desafio).
- Usuário do banco só com `CONNECT`: **implementado e validado na AWS em 14/10/2026** (autenticação IAM do RDS, [ADR 0013](docs/adr/0013-usuario-da-app-so-connect-via-iam.md), runbook em [`docs/usuario-db-iam.md`](docs/usuario-db-iam.md)): a role da API não lê o segredo master e, como `app_connect`, criar objetos ou virar master é negado. **Custo medido:** a autenticação IAM usa ~117 MiB de RAM e ~150 MiB de swap no `db.t4g.micro` (confirmado por A/B na mesma instância); 2 h de soak a 600 req/s com 0% de erro. Margem de memória fina; **decisão do Leandro (14/10): manter o IAM no `db.t4g.micro`** (ADR 0013). A app pré-aquece o token e a primeira conexão na partida, como mitigação do 503 da primeira conexão fria. Medido na AWS em 14/10: depois de um restart, o primeiro `/connect` deu 200 em 0,84 s; antes dava 503 em 2 s. Na primeiríssima partida, antes do `db-init`, o pré-aquecimento só registra o `28P01` e a app continua no ar. O `dev.tfvars` está em `db_iam_auth = true`; com `false` volta ao modo anterior (master).
- A role `gha-infra` cria roles e policies com prefixo `simple-api-*` com conteúdo livre (escalada dentro do prefixo). O IAM Access Analyzer não foi usado para validar as policies.
- (Resolvido em 14/10) O `infra.yml` tinha um job só, e a aprovação vinha antes de o plan ser visto. Hoje tem dois jobs (plan, depois gate e apply do plano revisado) e exige `confirm_destructive` em mudança destrutiva ([ADR 0009](docs/adr/0009-pipeline-com-oidc-e-um-environment-por-workflow.md)). Validado de ponta a ponta em 14/10 com a stack real:
  - apply: 54 added, hash conferido;
  - destroy sem confirmação: parou antes do gate (`delete=54`);
  - destroy confirmado: 54 destroyed.
- O `trivy-action` roda no job do `deploy.yml` que tem credenciais AWS temporárias, e o job `plan` do `ci.yml` executa HCL do próprio PR com a role de leitura.
- A saída das tasks em 443 e 53 para `0.0.0.0/0` é necessária sem NAT, mas é ampla.
- O SHA-256 do CA bundle da RDS é fixado por TOFU (a AWS não publica checksum). Em 14/10 a AWS trocou o arquivo e o build falhou como projetado. Conferi certificado a certificado: passou de 111 para 114, entraram só as 3 raízes da região sa-west-1 e nenhuma saiu. Depois disso atualizei o hash (PR #22).
- O repositório é público e o account id aparece nos logs das Actions (via OIDC): considerar torná-lo privado ao final.
- O hook local do gitleaks existe em [`.pre-commit-config.yaml`](.pre-commit-config.yaml) (mesma versão do CI, 8.30.1; instalar com `pip install pre-commit && pre-commit install`). Validado em 14/10/2026: bloqueia um segredo falso no stage (`github-pat`, exit 1) e passa sem nada staged. Ele só olha o que está staged; o histórico completo continua sendo coberto pelo `gitleaks git` do CI.

**DR**
- Um restore PITR real foi testado (13/10/2026): pedido até instância `available` em 15,4 min e marcador verificado em 16,4 min; RPO observado de ~3 a 8 min (uma execução, banco quase vazio). Em 14/10 repeti com a troca do endpoint e da policy IAM: restore 15,9 min + policy 4 s + troca 2,6 min = **18,5 min** até a app responder na instância restaurada (um piso: faltam a decisão e o `terraform apply`/`import`, não medidos); cópia entre regiões e snapshot entre contas não foram testados.
- Com a configuração atual de `dev`, o `destroy` apaga os dados e os backups automáticos ([`docs/dr.md`](docs/dr.md)).
- Replicação entre regiões e snapshot entre contas: só documentados, por escopo e por custo.

**Não implementado**
- Laboratório EKS: **implementado e validado só localmente e em CI, nunca aplicado na AWS** ([ADR 0007](docs/adr/0007-eks-somente-como-laboratorio-efemero.md), [ADR 0014](docs/adr/0014-lab-eks-com-argo-cd-core-e-nlb-interno.md), runbook em [`docs/eks-lab.md`](docs/eks-lab.md)): manifests Kustomize em `k8s/` testados no kind (15 de 15, incluindo 3 rolling restarts sem requisição falhada; o teste achou a falta de um `preStop`), root `infrastructure/eks-lab` com `terraform validate` e 9 testes, role `gha-eks-lab` e o workflow `eks-lab.yml`. O Argo CD observa a `main` (não a branch `gitops` da steering, por causa do account id; desvio registrado no ADR). Falta a janela de AWS: o formato do `overwrite:path`, a regra do VPC Link até o NLB e as permissões da `gha-eks-lab` só se validam lá.
- Notificação dos alarmes: o código cria três alarmes (crédito de CPU do RDS, espaço livre e respostas 5xx da API), mas `alarm_action_arns` é vazio por padrão, então nenhum alarme avisa ninguém.
- Rotina de atualização do digest da imagem e das dependências (Dependabot ou Renovate): não decidida.

**Valores `[PROPOSTA] a calibrar` no `dev.tfvars`:** throttling do estágio (50 req/s e burst 100; limita os testes pelo API Gateway), storage do RDS (20 GiB), retenção de logs (14 dias), TTL do registro SRV (10 s) e os limiares dos três alarmes.

**Divergências entre a steering e o código** (vale o código; nada foi alterado para bater com a documentação):
- A steering fala numa flag `ingress_mode = "alb"` que não existe no código.
- A estimativa da steering para 3 tasks via API Gateway assume throttling de 1.000 req/s no estágio; o `dev.tfvars` define 50.
- A estimativa de 500 req/s por task de 0,5 vCPU era conservadora: dentro da VPC a task sustentou 1.000 req/s sem erro.
