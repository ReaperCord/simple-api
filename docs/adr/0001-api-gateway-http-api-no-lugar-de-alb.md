# ADR 0001: API Gateway HTTP API no lugar de ALB

## Contexto

- O desafio lista como diferencial expor a API por API Gateway (HTTP API) integrado ao backend por VPC Link, para evitar o custo fixo do ALB. [FATO: [`infrastructure/README.md`](../../infrastructure/README.md) linha 215]
- O orçamento é fechado: créditos de US$ 100, gasto planejado de cerca de US$ 41, meta de no máximo US$ 45 e budget mensal de US$ 45 sem créditos. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Orçamento e estimativas"]
- Preços de referência em us-east-1: API Gateway HTTP API a US$ 1,00 por milhão de requisições (primeiros 300 milhões); IPv4 público a US$ 0,005/h. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Preços de referência", fontes aws.amazon.com/api-gateway/pricing e aws.amazon.com/vpc/pricing]
- A tabela de preços da steering não traz o ALB. A steering cita "cerca de US$ 24/mês com IPv4" sem fonte, então o valor do ALB fica **a verificar** na Pricing Calculator. [FATO: [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) tabela "Proibido sem pedido explícito"]
- O código cria uma HTTP API, a integração `HTTP_PROXY` por VPC Link, a rota `$default` e o estágio `$default` com throttling. [FATO: [`infrastructure/modules/apigw/main.tf`](../../infrastructure/modules/apigw/main.tf) linhas 1-49]
- Em integração privada o API Gateway inclui o nome do estágio no caminho enviado ao backend. O código sobrescreve com `overwrite:path` = `$request.path`. [FATO: [`modules/apigw/main.tf`](../../infrastructure/modules/apigw/main.tf) linhas 26-30]
- Os limites de throttling do `dev` são 50 req/s e burst 100, marcados `[PROPOSTA] a calibrar`. [FATO: [`dev.tfvars`](../../infrastructure/environments/dev.tfvars) linhas 93-94]

## Decisão

Expor a aplicação por API Gateway HTTP API (estágio `$default`, throttling no estágio), sem Application Load Balancer na trilha ECS.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| ALB público na frente do ECS (arquitetura alvo do autor) | Custo fixo por hora, **a verificar**. A steering cita ~US$ 24/mês com IPv4 sem fonte | Contraria o diferencial de FinOps do desafio. Ver [ADR 0012](0012-divergencia-da-arquitetura-alvo.md) |
| API Gateway REST API | **A verificar**. Preço não está na tabela da steering | Não foi avaliada. A HTTP API cobre o necessário (rota `$default`, throttling, VPC Link V2) |

## Consequências

- Sem load balancer, o `healthCheck` do container é o único sinal de saúde das tasks. [FATO: [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) seção "Autoscaling"]
- O custo passa a depender do volume: US$ 1,00 por milhão de requisições. Se a integração com o Cloud Map chamar `DiscoverInstances` a cada requisição, a steering estima US$ 2,00 por milhão. [HIPÓTESE: a doc da AWS não diz se há cache da descoberta; verificar no Cost Explorer após o primeiro teste de carga pelo API Gateway]
- O estágio aplica throttling. Com 50 req/s no `dev`, testes de carga e o spike precisam elevar o limite temporariamente, senão o que se mede é o 429. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Testes de carga e custo"]
- A API é pública e sem autenticação (contrato do desafio). O API Gateway é a única proteção, via throttling. [FATO: [`docker-compose.yml`](../../docker-compose.yml) linhas 4-5]
- Nada disso foi aplicado na AWS. O CI roda `terraform fmt`, `validate` e `test` sem credenciais, e o job `plan` só roda quando a variável `PLAN_ENABLED` é `true` (o ARN da role fica num secret, que não pode ser lido no `if` de um job), o que depende do bootstrap. Não há `plan` nem `apply` real. [FATO: [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) linhas 130-170 e 291-294; ver [Pendências no README](../../README.md#pendências)]

## Status

Aceito. Decisão travada em [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md). Implementada no código, não aplicada na AWS.
