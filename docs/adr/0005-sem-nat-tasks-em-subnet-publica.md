# ADR 0005: Sem NAT Gateway, tasks em subnet pública com SG restrito

## Contexto

- As tasks precisam sair para a internet em 443 para três destinos: puxar a imagem do ECR, enviar logs ao CloudWatch e ler o segredo no Secrets Manager. [FATO: policies da execution role e da task role em [`main.tf`](../../infrastructure/main.tf) linhas 239-277]
- Nesta trilha não há NAT nem VPC endpoints. As subnets privadas só têm a rota local. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 129-134]
- Preços de referência em us-east-1: NAT Gateway a US$ 0,045/h mais US$ 0,045/GB (a página de preços dá o exemplo em Ohio; conferir us-east-1); IPv4 público a US$ 0,005/h. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Preços de referência", fonte aws.amazon.com/vpc/pricing]
- A steering cita VPC interface endpoints a cerca de US$ 7,30/mês cada, por AZ, sem fonte. O valor fica **a verificar**. [FATO: [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) tabela "Proibido sem pedido explícito"]
- As tasks recebem IP público (`assign_public_ip = true`) nas subnets públicas, que têm `map_public_ip_on_launch = true`. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 74-82 e 314]
- O SG das tasks aceita entrada só do SG do VPC Link, na porta 3000. O módulo de SG rejeita ingress para `0.0.0.0/0` ou `::/0`. [FATO: [`rules-sg-ecs.json`](../../infrastructure/config/security_rules/rules-sg-ecs.json) linhas 3-10 e [`modules/security/security-group/variables.tf`](../../infrastructure/modules/security/security-group/variables.tf) linhas 61-66]
- O Trivy marca `AWS-0164` (subnet pública com IP público) e a exceção está registrada com justificativa e data. [FATO: [`infrastructure/.trivyignore`](../../infrastructure/.trivyignore)]

## Decisão

Não instanciar NAT Gateway nem VPC endpoints. As tasks ficam em subnets públicas com IP público, e o isolamento vem do security group: entrada só do SG do VPC Link. O RDS e o VPC Link ficam em subnets privadas sem rota de saída.

## Alternativas consideradas

Cálculos com 730 horas por mês (convenção de cálculo):

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| Tasks em subnet privada com NAT Gateway (arquitetura alvo) | US$ 0,045/h = US$ 32,85/mês, mais US$ 0,045/GB de tráfego processado (valor de Ohio, conferir us-east-1) | Maior item fixo da stack. Ver [ADR 0012](0012-divergencia-da-arquitetura-alvo.md) |
| Tasks em subnet privada com VPC interface endpoints (ECR API, ECR DKR, Logs, Secrets Manager) | **A verificar**. A steering cita ~US$ 7,30/mês por endpoint e por AZ, sem fonte | A steering conclui que sai mais caro que IPv4 público neste porte. Não foi recalculado com preço oficial |
| Tasks em subnet pública com IP público (escolhida) | US$ 0,005/h por IP = US$ 3,65/mês por task | Escolhida. Com o autoscaling no máximo de 3 tasks, 3 × 3,65 = US$ 10,95/mês enquanto as 3 existirem |

## Consequências

- Cada task em execução ocupa um IPv4 público e custa US$ 0,005/h. O autoscaling aumenta esse custo junto com as tasks.
- A task tem endereço público, mas nenhuma regra de entrada além do SG do VPC Link. Portas fechadas por SG não respondem à internet. [HIPÓTESE: não houve teste de varredura de portas; a garantia vem da configuração do SG]
- A saída em 443 e 53 para `0.0.0.0/0` fica aberta. Um processo comprometido na task poderia falar com qualquer destino HTTPS. Não há mitigação por lista de destinos. [FATO: [`rules-sg-ecs.json`](../../infrastructure/config/security_rules/rules-sg-ecs.json) linhas 12-36]
- O tráfego para o ECR, o CloudWatch e o Secrets Manager passa pelo Internet Gateway, não por rede privada da AWS. [HIPÓTESE: o caminho exato dos endpoints públicos da AWS não foi inspecionado]
- O módulo `nat-gateway` e a rota de `config/routes/private.json` ficam no repositório sem uso, e o CI verifica que o grafo da raiz não os contém. [FATO: [`ci.yml`](../../.github/workflows/ci.yml) linhas 182-205]
- A conectividade real das tasks até ECR, Logs e Secrets Manager por IP público não foi exercitada na AWS.

## Status

Aceito. Decisão travada em [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md). Implementada no código, não aplicada na AWS.
