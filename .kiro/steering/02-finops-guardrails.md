---
inclusion: always
---

# Guardrails de FinOps

## Antes de qualquer ação que crie recurso na AWS

Responda, por escrito, ANTES de pedir aprovação:

1. Quais recursos serão criados/alterados/destruídos (saída de `terraform plan`, resumida)
2. Custo por hora e por mês de cada recurso novo, com a fonte (URL oficial) ou "a verificar"
3. O que continua cobrando depois de `terraform destroy` (snapshots, log groups, imagens ECR, EIPs, volumes, zonas do Route 53)
4. Por quanto tempo ficará ligado
5. Se o serviço/tipo de instância é aceito na conta (o Free plan restringe; a conta aberta pelo cadastro novo também) — se o plano ainda é desconhecido, diga isso

Sem os 5 itens, não peça aprovação. Sem aprovação explícita NO TURNO, não execute. Por padrão o agente só tem credencial de leitura: a execução é feita pelo Leandro (que pode ativar um perfil de escrita e aprovar o comando no Kiro) ou pelo workflow `infra.yml` com aprovação.

## Preços de referência (us-east-1)

| Item | Preço | Fonte |
|---|---|---|
| EKS control plane, suporte padrão / estendido | US$ 0,10/h / US$ 0,60/h | aws.amazon.com/eks/pricing |
| Fargate x86 | US$ 0,04048/vCPU-h + US$ 0,004446/GB-h | aws.amazon.com/fargate/pricing |
| Fargate ARM64 | US$ 0,03238/vCPU-h + US$ 0,00356/GB-h | idem |
| API Gateway HTTP API | US$ 1,00/milhão (primeiros 300 M) | aws.amazon.com/api-gateway/pricing |
| Cloud Map | US$ 0,10 por recurso registrado/mês; US$ 1,00 por milhão de chamadas de descoberta | aws.amazon.com/cloud-map/pricing |
| Zona privada do Route 53 | US$ 0,50/mês | idem (referência ao Route 53) |
| IPv4 público (em uso ou ocioso) | US$ 0,005/h | aws.amazon.com/vpc/pricing |
| NAT Gateway | US$ 0,045/h + US$ 0,045/GB (exemplo da página em Ohio; conferir us-east-1) | idem |
| RDS T4g Unlimited acima do baseline | US$ 0,075/vCPU-h | aws.amazon.com/rds/postgresql/pricing |
| AWS Budgets sem ações | gratuito | aws.amazon.com/aws-cost-management/aws-budgets/pricing |
| RDS db.t4g.micro on-demand | ~US$ 0,016/h — APROXIMADO | Pricing Calculator |
| EC2 t4g.small on-demand / t4g.medium Spot | ~US$ 0,0168/h / ~US$ 0,01–0,015/h — APROXIMADOS | Pricing Calculator / histórico de Spot |

Qualquer preço fora desta tabela: buscar fonte oficial ou marcar "a verificar". Nunca estimar de memória e apresentar como fato.

## Orçamento e estimativas

- Créditos: US$ 100. Planejado ~US$ 41 (meta ≤ US$ 45). Teto pessoal: R$ 50 (relevante só no Paid plan).
- Stack ECS 24x7: ~US$ 34/mês (RDS ~14, task 0,5 vCPU ARM ~14,42, IPv4 3,65, resto ~2). Lab EKS: ~US$ 0,17/h.
- Risco aberto: se o API Gateway chamar `DiscoverInstances` a cada requisição, o custo por requisição vai de US$ 1 para US$ 2 por milhão. Verificar no Cost Explorer (linha do Cloud Map) após o primeiro teste de carga.
- **AWS Budgets** (no bootstrap, ANTES do primeiro apply da stack): UM budget mensal de US$ 45 com alertas de gasto REAL em US$ 5 (anomalia cedo), 50%, 80% e 100%.
  - **Excluir créditos** (`cost_types.include_credit = false` no Terraform; o padrão é `true`): com créditos incluídos o custo líquido fica zerado e nenhum alerta dispara.
  - Não depender de alerta de PREVISÃO: a AWS precisa de ~5 semanas de histórico para gerar previsão.
  - O billing atualiza ao menos 1×/dia: budget não é disjuntor; quem corta gasto é o `destroy` e o TTL.

## Tags obrigatórias (via `default_tags` do provider)

`Project=simple-api`, `Env=<dev|hml|prod>`, `Track=<ecs|eks|shared|bootstrap>`, `Owner=leandro`, `ManagedBy=terraform`, `TTL=<data ISO ou "none">`. Recursos do root `bootstrap` (bucket de state, OIDC, roles do pipeline, budget, ECR) levam `Track=bootstrap` e são ignorados pela varredura de resíduos.

## Testes de carga e custo

- Stress, breakpoint e soak rodam DE DENTRO da VPC (task k6 → IPs das tasks obtidos com `discover-instances`), com autoscaling desligado: não passam pelo API Gateway.
- Pelo API Gateway: smoke, baseline, uma série de load (abaixo do throttling) e o spike. Para o spike, subir temporariamente o throttling do estágio acima da carga do teste, senão o que se mede é o 429 do throttling. Antes de rodar, calcule: requisições totais × US$ 1/milhão (× 2 se a descoberta do Cloud Map for cobrada por requisição) e peça aprovação.
- T4g do RDS acima do baseline cobra crédito de CPU: anote a duração dos testes de estresse.

## Depois de destroy

Rodar `tools/residual-check.sh` e mostrar a saída. Destroy sem varredura = tarefa incompleta. Código de saída 2 (erro de consulta) NÃO significa "limpo"; recursos com `Track=bootstrap` não contam.
