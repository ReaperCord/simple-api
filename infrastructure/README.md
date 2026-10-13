# Simple-api — Infraestrutura (Terraform)

Infraestrutura como código (IaC) para provisionar e expor publicamente a **simple-api** (Node.js + PostgreSQL) na AWS, usando Amazon ECS (Fargate) atrás de um Application Load Balancer, dentro de uma VPC isolada criada por você.

Este repositório faz parte do **Desafio Técnico KXC**. O objetivo não é só "fazer rodar", mas avaliar como você estrutura ambientes em nuvem, automatiza entregas e organiza sua infraestrutura (organização, segurança e resiliência).

---

## ⚠️ Aviso importante — particularidades intencionais

> Como em qualquer projeto real, **este repositório contém erros e "pegadinhas" propositais**, colocados intencionalmente para avaliar sua análise crítica.
>
> Não assuma que tudo está correto. Antes de aplicar, **revise criticamente** se todas as informações, portas, regras de rede e variáveis estão coerentes com a aplicação — ou se algo precisa de ajuste.

Áreas que merecem atenção especial (sem dar a resposta pronta):

- **Portas**: confira em qual porta a aplicação realmente escuta (veja o `README.md` e o código em `application/`) e compare com o que está configurado na infraestrutura.
- **Security Groups**: revise as regras em `config/security_rules/`. Verifique se o fluxo *internet → ALB → ECS → aplicação* está realmente liberado ponta a ponta.
- **Encadeamento dos módulos**: o ALB, o Target Group e o Listener estão em módulos separados e precisam ser conectados corretamente entre si e ao serviço ECS.
- **Placeholders**: alguns arquivos de config usam marcadores como `${ALB_SG_ID}` e `${NAT_GW_ID}` que precisam ser resolvidos na composição raiz.
- **Arquivos de composição**: `main.tf` e `variables.tf` (raiz) estão propositalmente vazios, e os `*.tfvars` estão incompletos — cabe a você montar a chamada dos módulos e completar as variáveis.

Documente os problemas que encontrou e como os corrigiu. Isso faz parte da avaliação.

---

## Implementação atual (trilha ECS)

A composição em `main.tf` segue a trilha decidida em `.kiro/steering/01-arquitetura-e-restricoes.md`: API Gateway HTTP API → VPC Link V2 → Cloud Map (registro SRV) → ECS Fargate ARM64 (0,5 vCPU / 1 GB) → RDS PostgreSQL privado. As seções abaixo descrevem como ela difere da "arquitetura alvo" do desafio e como operar.

### Divergências conscientes

A "arquitetura alvo" abaixo (ALB + NAT) é a do autor do desafio. A implementação diverge de propósito:

| Tema | Arquitetura alvo do autor | Trilha atual |
|---|---|---|
| Entrada | Application Load Balancer público | API Gateway HTTP API com VPC Link V2 e Cloud Map (SRV) |
| Saída das subnets privadas | NAT Gateway | Sem NAT: subnets privadas só com a rota local (RDS e VPC Link) |
| Tasks ECS | Subnets privadas | Subnets públicas com IP público; o SG aceita só o SG do VPC Link |
| Módulos `alb`, `target-group`, `listener`, `nat-gateway` | Instanciados | Mantidos no repositório e NÃO instanciados (alternativa futura) |
| Regra de SG da task | Origem no ALB | Origem no SG do VPC Link, por chave simbólica (`sg_refs`) |

Motivo: evitar o custo fixo do ALB e do NAT, conforme os guardrails de FinOps do projeto (`.kiro/steering/02-finops-guardrails.md`, que traz os preços com fonte). A decisão está registrada no [ADR 0012](../docs/adr/0012-divergencia-da-arquitetura-alvo.md).

### Trade-off de `ignore_changes` e `skip_destroy`

- O `aws_ecs_service` tem `lifecycle { ignore_changes = [task_definition, desired_count] }`. O Terraform cria a revisão inicial da task definition; o pipeline (`deploy.yml`) registra as seguintes e chama `UpdateService`. O autoscaling controla o `desired_count`.
- Consequência: mudar variável de ambiente, CPU, memória ou `healthCheck` pelo Terraform NÃO chega ao service depois da criação. Só um deploy pelo pipeline aplica a mudança.
- **Revise todo `terraform plan` que mostre `aws_ecs_service` "must be replaced"** antes de aprovar o apply: o `ignore_changes` não protege contra recriação por mudança de argumentos que forçam novo recurso.
- A task definition tem `skip_destroy = true`: o Terraform não desregistra a revisão antiga ao substituí-la ou destruí-la, para o service não ficar apontando para uma revisão inativa durante um replace. Resíduo: após um `destroy` as revisões de task definition continuam registradas na conta (sem tasks em execução); remova-as à parte se quiser limpar.

### Validação local (sem AWS, sem `plan`)

```powershell
terraform fmt -check -recursive infrastructure
terraform -chdir=infrastructure/bootstrap init -backend=false -input=false -lockfile=readonly
terraform -chdir=infrastructure/bootstrap validate
terraform -chdir=infrastructure init -backend=false -input=false -lockfile=readonly
terraform -chdir=infrastructure validate
# por módulo (init -backend=false + validate) e, nos módulos com tests/:
terraform -chdir=infrastructure/modules/oidc test
```

O `terraform plan` não roda nesta validação: os data sources (`aws_availability_zones`, `aws_ecr_repository`) exigem a AWS, e o plan real é uma etapa à parte, só com credencial de leitura (`kxc-readonly`) e `-lock=false`. Os lockfiles dos dois roots (`.terraform.lock.hcl`, `hashicorp/aws` 6.68.0 com hashes para `windows_amd64`, `linux_amd64`, `linux_arm64` e `darwin_arm64`) são versionados; os dos módulos não.

### Ordem de execução: bootstrap → primeira imagem → stack

1. **Bootstrap** (uma vez, state local; o `terraform.tfstate` é sensível e nunca é versionado):
   copie `bootstrap/terraform.tfvars.example` para `bootstrap/secrets.tfvars` (ignorado pelo git), troque `<GITHUB_OWNER>` e `<EMAIL>` e rode `init`, `plan -var-file=secrets.tfvars` e, com aprovação explícita, `apply`. Cria o bucket de state, o ECR, o budget e o OIDC com `gha-plan`, `gha-deploy` e `gha-infra`.
2. **GitHub**: crie os environments `deploy` e `infra` (só a branch `main`; aprovação obrigatória no `infra`) e as variáveis do repositório com as saídas do bootstrap: `AWS_PLAN_ROLE_ARN`, `AWS_DEPLOY_ROLE_ARN`, `AWS_INFRA_ROLE_ARN`, `TF_STATE_BUCKET`, `TF_STATE_KEY` e `AWS_REGION`.
3. **Primeira imagem**: `deploy.yml` com `only_build=true` publica a imagem (tag = SHA do commit) no ECR. Sem ela a task não sobe.
4. **Stack**: `infra.yml` (ou, localmente com perfil de escrita ativado pelo Leandro) roda
   `terraform init -backend-config="bucket=<TF_STATE_BUCKET>" -backend-config="key=<TF_STATE_KEY>" -backend-config="region=<AWS_REGION>"` e depois `plan`/`apply` com `-var-file=environments/dev.tfvars -var image_tag=<sha>`.
5. **Depois da janela de avaliação**: `terraform destroy` e `tools/residual-check.sh`. O bootstrap (bucket de state, ECR, budget, OIDC) permanece.

---

## Arquitetura alvo

```
                 Internet
                    │
                    ▼
          ┌───────────────────┐
          │  Application LB   │  (subnets públicas)
          │  Listener → TG    │
          └─────────┬─────────┘
                    │  (forward)
                    ▼
          ┌───────────────────┐
          │  ECS Service      │  (Fargate, subnets privadas)
          │  Task: simple-api │
          └─────────┬─────────┘
                    │
                    ▼
          ┌───────────────────┐
          │  PostgreSQL (RDS) │  (diferencial)
          └───────────────────┘
```

- **VPC isolada** com subnets públicas e privadas em 2 AZs.
- **Internet Gateway** para as subnets públicas e **NAT Gateway** para saída das subnets privadas.
- **ALB** público encaminhando para um **Target Group** (`target_type = ip`, Fargate) via **Listener**.
- **ECS Fargate** rodando o container da aplicação nas subnets privadas.
- **Security Groups** segregados para ALB e ECS.
- **IAM Roles** (execução da task e role da aplicação) seguindo *least privilege*.
- **Parameter Store** para variáveis/segredos da aplicação.

---

## Estrutura do repositório

```
infrastructure/
├── versions.tf             # terraform >= 1.11, aws ~> 6.68, backend "s3" parcial
├── providers.tf            # provider com default_tags
├── main.tf                 # composição raiz dos módulos (trilha ECS)
├── variables.tf
├── outputs.tf
├── .terraform.lock.hcl     # versionado (aws 6.68.0)
├── bootstrap/              # root aplicado uma vez, state LOCAL: bucket de state, ECR, budget, OIDC
├── environments/
│   ├── dev.tfvars
│   ├── hml.tfvars
│   └── prod.tfvars
├── config/
│   ├── policies/           
│   ├── routes/             
│   └── security_rules/     
└── modules/
    ├── network/
    │   ├── vpc/
    │   ├── subnet/
    │   ├── internet-gateway/
    │   ├── nat-gateway/
    │   ├── route/
    │   ├── route-table/
    │   ├── route-table-association/
    │   ├── alb/                     
    │   ├── target-group/            
    │   └── listener/                
    ├── security/
    │   ├── security-group/
    │   ├── iam-role/
    │   └── parameter-store/
    ├── ecs/                         # cluster + task definition + service (Fargate)
    ├── ecr/                         # repositório IMMUTABLE com scan e lifecycle
    ├── rds/                         # PostgreSQL privado, senha gerenciada pelo RDS
    ├── cloudmap/                    # namespace privado + serviço SRV
    ├── apigw/                       # HTTP API + VPC Link V2 + integração + estágio $default
    ├── autoscaling/                 # target tracking de CPU
    ├── budget/                      # AWS Budgets (include_credit = false)
    └── oidc/                        # provider OIDC do GitHub + roles gha-plan, gha-deploy, gha-infra
```

Os recursos estão separados em módulos para você compor o encadeamento e expor seu raciocínio de organização.

---

## Fluxo esperado

1. **Fork** deste repositório.
2. **Containerização**: crie um `Dockerfile` otimizado para a aplicação em `application/`.
3. **Composição da IaC**: monte o `main.tf` (raiz) chamando os módulos na ordem correta de dependência:
   `vpc → subnets → igw/nat → route-tables/routes → security-groups → alb → target-group → listener → iam → ecs`.
4. **Variáveis**: declare-as em `variables.tf` e preencha os `environments/*.tfvars` (a seção de rede do `dev.tfvars` já está pronta como referência de padrão).
5. **Revisão crítica**: valide as particularidades sinalizadas acima (portas, SGs, placeholders) e ajuste o que estiver incorreto.
6. **Provisionamento**: aplique com Terraform (veja abaixo).
7. **CI/CD**: crie a pipeline (GitHub Actions, GitLab CI ou CodePipeline) que faça o build da imagem, push para o ECR e deploy no ECS.
8. **Validação**: confirme que a API responde publicamente pela URL do ALB (`GET /` e `GET /connect`).

---

## Como executar

> Texto original do desafio. Para esta implementação siga a seção "Ordem de execução: bootstrap → primeira imagem → stack" acima (o backend é S3 parcial e o Terraform exigido é >= 1.11).

Pré-requisitos: Terraform >= 1.5, credenciais AWS configuradas, aplicação já publicada no ECR.

```bash
cd infrastructure

# Inicializa providers e módulos
terraform init

# Revisa o plano para o ambiente desejado
terraform plan -var-file=environments/dev.tfvars

# Aplica
terraform apply -var-file=environments/dev.tfvars
```

Para validar os módulos isoladamente:

```bash
terraform fmt -recursive
terraform validate
```

---

## Requisitos e diferenciais do desafio

**Obrigatórios**
- Containerização com Dockerfile otimizado.
- Infraestrutura base 100% em Terraform (sem deploy manual pelo console).
- Pipeline de CI/CD com build + deploy automático.
- VPC nova e isolada.

**Diferenciais**
- Serviços gerenciados (ECS/EKS).
- PostgreSQL no Amazon RDS (em vez de container solto).
- Módulos Terraform bem estruturados (não tudo em um único `main.tf`).
- *Least privilege* nas roles da pipeline e da aplicação.
- **FinOps**: expor a API via **API Gateway** (HTTP API) integrado ao backend (VPC Link para o ECS ou serverless) para se manter no Free Tier, evitando o custo fixo do ALB.

---

## Entrega

Entregue mesmo que não conclua todos os passos. **Documente o que faltou, os problemas intencionais que identificou e como resolveria cada um.** O objetivo é entender seu momento técnico e seu raciocínio para resolver problemas.

---

<p align="center">
  desenvolvido e criado por<br>
  <strong>José Neto</strong><br>
  Cloud Architect | Squad Leader
</p>
