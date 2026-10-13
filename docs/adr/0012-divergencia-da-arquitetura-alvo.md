# ADR 0012: Divergência consciente da "arquitetura alvo" (ALB e NAT) do README de infraestrutura

## Contexto

- O [`infrastructure/README.md`](../../infrastructure/README.md) traz uma "Arquitetura alvo" do autor do desafio: ALB público em subnets públicas, ECS Fargate em subnets privadas, NAT Gateway para a saída das subnets privadas, Security Groups para ALB e ECS e Parameter Store para variáveis e segredos. [FATO: [`infrastructure/README.md`](../../infrastructure/README.md) linhas 78-107]
- O mesmo README pede o ALB no fluxo esperado (`vpc → subnets → igw/nat → route-tables → security-groups → alb → target-group → listener → iam → ecs`) e depois cita, como diferencial de FinOps, expor a API por API Gateway para evitar o custo fixo do ALB. [FATO: [`infrastructure/README.md`](../../infrastructure/README.md) linhas 164-165 e 215]
- A ordem de autoridade do projeto diz que, em decisão de arquitetura (ALB, NAT, tamanho de task, região), vale a steering, mesmo que o README original descreva outra coisa, e que a divergência vai documentada em ADR. [FATO: [`AGENTS.md`](../../AGENTS.md) seção "Ordem de autoridade"]
- A steering travou: sem ALB e sem NAT na trilha ECS. [FATO: [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) seção "Módulos e arquivos do repo que NÃO entram na trilha principal"]
- Preços de referência: NAT Gateway a US$ 0,045/h mais US$ 0,045/GB (exemplo da página em Ohio; conferir us-east-1); IPv4 público a US$ 0,005/h. O ALB não está na tabela, então fica **a verificar**. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Preços de referência"]
- O budget mensal é de US$ 45, sem créditos, e o gasto planejado da stack ECS é cerca de US$ 34/mês em 24x7. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Orçamento e estimativas"]

## Decisão

Divergir da arquitetura alvo do autor, de propósito, nos pontos abaixo. Os módulos `alb`, `target-group`, `listener` e `nat-gateway` e os arquivos `rules-sg-alb.json` e `config/routes/private.json` ficam no repositório e **não são instanciados**.

| Tema | Arquitetura alvo do autor | Trilha atual | Onde está documentado |
|---|---|---|---|
| Entrada | Application Load Balancer público | API Gateway HTTP API, VPC Link V2 e Cloud Map (SRV) | [ADR 0001](0001-api-gateway-http-api-no-lugar-de-alb.md), [ADR 0002](0002-vpc-link-v2-e-cloud-map-srv.md) |
| Saída das subnets privadas | NAT Gateway | Sem NAT. Subnets privadas só com rota local (RDS e VPC Link) | [ADR 0005](0005-sem-nat-tasks-em-subnet-publica.md) |
| Tasks ECS | Subnets privadas | Subnets públicas com IP público. O SG aceita só o SG do VPC Link | [ADR 0005](0005-sem-nat-tasks-em-subnet-publica.md) |
| Origem da regra de SG da task | SG do ALB (`${ALB_SG_ID}`) | SG do VPC Link, por chave simbólica | [ADR 0010](0010-regras-de-sg-por-chaves-simbolicas.md) |
| Segredos | Parameter Store | Secrets Manager gerenciado pelo RDS, com rotação. O módulo `parameter-store` não é usado | [ADR 0006](0006-tls-verify-full-e-segredo-gerenciado-pelo-rds.md) |
| Banco | "Diferencial" | RDS PostgreSQL `db.t4g.micro` single-AZ, privado | [ADR 0004](0004-rds-postgresql-db-t4g-micro-single-az-privado.md) |
| Porta do ECS | 8084 na regra de SG do repositório base | 3000, a porta real da aplicação | [`docs/arquitetura.md`](../arquitetura.md) |

## Alternativas consideradas

Cálculos com 730 horas por mês (convenção de cálculo, não preço da AWS):

| Alternativa | Custo | Motivo |
|---|---|---|
| Seguir a arquitetura alvo (ALB e NAT) | NAT: 0,045 × 730 = US$ 32,85/mês, mais US$ 0,045/GB. ALB: **a verificar** | O NAT sozinho se aproxima do que a stack ECS inteira custa por mês (~US$ 34 em 24x7, estimativa da steering). Contraria o diferencial de FinOps |
| ALB com tasks em subnet pública, sem NAT | ALB: **a verificar** | Mantém o custo fixo do ALB. O diferencial pedido é o API Gateway |
| ALB e API Gateway juntos | Soma dos dois | Sem ganho funcional |

## Consequências

- Quem avalia esperando o fluxo `internet → ALB → ECS` encontrará outro desenho. Este ADR, o [README](../../README.md) e [`docs/arquitetura.md`](../arquitetura.md) existem para explicar a escolha.
- Os módulos `alb`, `target-group` e `listener` ainda existem e são alcançáveis pelo bloco opcional `load_balancer` do módulo `ecs` (variável `target_group_arn`). A steering fala em uma flag `ingress_mode = "alb"` para ativá-los, mas essa flag **não existe** no código. Voltar ao ALB exigiria compor os módulos na raiz. [FATO: [`modules/ecs/main.tf`](../../infrastructure/modules/ecs/main.tf) linhas 107-115 e busca por `ingress_mode` nos `.tf` da raiz e do módulo `ecs`]
- Os módulos de ALB têm achados do Trivy (`AWS-0052`, `AWS-0053`) ignorados com justificativa porque não são instanciados. Devem ser corrigidos antes de qualquer uso. [FATO: [`infrastructure/.trivyignore`](../../infrastructure/.trivyignore)]
- O CI falha se `aws_nat_gateway`, `aws_lb` ou `aws_alb` aparecerem no grafo da raiz, ou se os módulos proibidos forem instanciados. [FATO: [`ci.yml`](../../.github/workflows/ci.yml) linhas 182-205]
- O [`infrastructure/README.md`](../../infrastructure/README.md) ainda diz, na linha 43, que este ADR "ainda não foi escrito". Essa linha não foi editada nesta entrega. Atualizá-la é um ajuste de uma linha.
- O custo do ALB e a comparação de custo total com a arquitetura alvo não foram calculados. **A verificar** na Pricing Calculator.

## Status

Aceito. Decisão travada pelo Leandro em [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md). Implementada no código, não aplicada na AWS.
