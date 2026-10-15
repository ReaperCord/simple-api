# Custo real da janela de 13/10/2026 (Cost Explorer)

Consulta de 14/10/2026 à API do Cost Explorer (`get-cost-and-usage`, `UnblendedCost`, diário). O Cost Explorer devolve por padrão o valor **líquido de créditos**; abaixo está o **bruto** (filtro `RecordType = Usage`). O dia 13/10 vem marcado como **estimado** pela AWS e pode mudar um pouco.

## Resumo

| Item | Valor |
|---|---|
| Uso bruto em 13/10 (toda a janela) | **US$ 1,454** |
| Créditos aplicados | US$ -1,454 (custo líquido do dia: US$ 0,00) |
| Saldo de crédito restante (`get-account-plan-state`) | **US$ 138,52** (antes US$ 140) |
| 12/10 e 14/10 | US$ 0,00 |

Os valores estimados antes de cada etapa ficaram acima do real: carga parte B (≤ US$ 0,25), spike (≤ US$ 2,3), restore (≲ US$ 0,05) e a stack ligada, somando um teto bem acima de US$ 1,45.

## Por serviço (bruto, 13/10)

| Serviço | US$ | Observação |
|---|---|---|
| Amazon API Gateway | 1,0782 | 1.078.187 requisições × US$ 1,00/milhão (smoke, baseline, spike e testes) |
| Amazon ECS (Fargate) | 0,2017 | API ARM64 + gerador x86 (ver abaixo) |
| AWS Cloud Map | 0,0729 | 72.921 chamadas de API × US$ 1,00/milhão |
| Amazon RDS | 0,0590 | instância 3,09 h + storage gp3 |
| Amazon VPC (IPv4 público) | 0,0288 | 5,77 horas-IP × US$ 0,005 |
| AWS Cost Explorer | 0,0100 | 1 chamada minha na véspera (US$ 0,01 por chamada) |
| AWS Secrets Manager | 0,0028 | segredo do RDS |
| S3 + ECR | 0,0005 | |
| **Total** | **1,4540** | |

## Detalhe por tipo de uso (bruto, 13/10)

| Tipo de uso | Quantidade | US$ | Preço efetivo |
|---|---|---|---|
| API Gateway `ApiGatewayHttpRequest` | 1.078.187 | 1,07819 | US$ 1,00/milhão |
| Cloud Map `Cloud-Map-API-Calls` | 72.921 | 0,07292 | US$ 1,00/milhão |
| Fargate ARM vCPU-h | 2,29 | 0,07429 | US$ 0,0324/h (tabela: 0,03238) |
| Fargate ARM GB-h | 4,59 | 0,01633 | US$ 0,00356/h (tabela) |
| Fargate x86 vCPU-h (gerador k6) | 2,19 | 0,08885 | US$ 0,0406/h (tabela: 0,04048) |
| Fargate x86 GB-h (gerador k6) | 4,39 | 0,01951 | US$ 0,00444/h (tabela: 0,004446) |
| RDS `db.t4g.micro` | 3,09 h | 0,04948 | US$ 0,0160/h (estimativa usada: ~0,016) |
| RDS GP3 storage | 0,08 GB-mês | 0,00956 | |
| IPv4 público em uso | 5,77 h | 0,02883 | US$ 0,0050/h (tabela) |

Os preços efetivos conferem com a tabela de `02-finops-guardrails.md`. Nenhum item de custo inesperado (sem NAT, ALB, EKS ou instâncias EC2).

## Resposta à dúvida do Cloud Map ("cobra `DiscoverInstances` por requisição?")

- O Cloud Map **cobra por chamada de API** (US$ 1,00 por milhão), mas as chamadas foram **72.921 para 1.078.187 requisições** do API Gateway, ou seja, **~1 chamada para cada ~15 requisições** (razão 0,068).
- Logo o custo **não** dobrou o do API Gateway por requisição, como era o pior caso da steering: o adicional foi +6,8% (US$ 0,073 sobre US$ 1,078).
- Isso é consistente com cache ou agrupamento da descoberta pelo API Gateway, mas o **mecanismo não foi verificado**. A conta do Cloud Map também inclui chamadas que não vêm do tráfego (registro e saúde pelo ECS e as minhas consultas `list-services`/`list-instances` do monitor), então 0,068 é um **limite superior** da razão de `DiscoverInstances` por requisição.
- Escopo: uma janela, com o tráfego do spike dominando (1 task a 3 tasks); a razão pode variar com o padrão de carga.

## Limites

- 13/10 é dado estimado; o valor final da fatura pode diferir.
- As chamadas ao Cost Explorer de 14/10 (cerca de 12, a US$ 0,01 cada, ≈ US$ 0,12) só aparecerão na fatura de amanhã.
- O custo das partes (A, B, spike, restore) não está separado por etapa: o Cost Explorer diário agrupa o dia inteiro.

# Janelas 2 e 3 (14/10/2026) e teste do `infra.yml` (Cost Explorer)

Consulta de 15/10/2026, às 09:35 de Brasília. Mesmo método: `UnblendedCost` diário, bruto (`RecordType = Usage`), 3 chamadas à API (~US$ 0,03, que aparecem na fatura de 16/10). **Os dias do Cost Explorer são em UTC:**

- **14/10 UTC** (21:00 de 13/10 a 21:00 de 14/10, em Brasília): a janela 2 inteira (soak, séries, A/B do IAM, DR) e a janela 3 até 21:00.
- **15/10 UTC:** o fim da janela 3 (21:00 a 22:14) e o teste de ponta a ponta do `infra.yml` (23:38 a 23:57). O dia ainda está aberto, então o dado é parcial.

Todos os dias vêm marcados como **estimados** pela AWS.

## Resumo

| Dia (UTC) | Uso bruto | Créditos | Líquido |
|---|---|---|---|
| 13/10 (janela 1, valor atualizado) | US$ 1,4762 (antes 1,454) | -1,4762 | 0,00 |
| 14/10 | **US$ 1,2829** | -1,2829 | 0,00 |
| 15/10 (parcial) | **US$ 0,2134** | -0,2134 | 0,00 |

O saldo de crédito (`get-account-plan-state`) está em **US$ 157,03**. Ele **subiu** US$ 18,51 em relação aos US$ 138,52 de 14/10, embora 14 e 15/10 tenham consumido US$ 1,50. Isso equivale a ~US$ 20 creditados no período. O Free plan dá créditos extras por atividades concluídas, e a provável é a primeira instância EC2 (os nós do EKS), mas **isso não foi verificado** na tela de créditos.

## Por serviço (bruto)

| Serviço | 14/10 | 15/10 (parcial) | Observação |
|---|---|---|---|
| ECS (Fargate) | 0,5080 | 0,0259 | API ARM64 (4,42 + 0,66 vCPU-h) e gerador x86 da janela 2 (6,17 vCPU-h: soak de 2 h e séries) |
| EKS (plano de controle) | 0,3323 | 0,1104 | **4,43 h** no total, a US$ 0,10/h (estimativa: ~4,6 h) |
| RDS | 0,1740 | 0,0269 | `db.t4g.micro` 9,11 + 1,41 h, mais storage gp3 |
| Cost Explorer | 0,1200 | | as 12 chamadas de 14/10 |
| VPC (IPv4 público) | 0,0899 | 0,0173 | 17,99 + 3,45 horas-IP, incluindo os IPs dos nós do EKS |
| Elastic Load Balancing (NLB do lab) | 0,0450 | 0,0225 | 3 horas cobradas (por hora iniciada; estimativa: ~2,7 h) |
| EC2 (outros: EBS dos nós, transferência) | 0,0058 | 0,0066 | |
| Secrets Manager, API Gateway, S3 | 0,0075 | 0,0037 | |
| **Instâncias EC2 `t4g.small` (nós do EKS)** | **0** | **0** | 5,86 + 2,09 h **cobertas pelo Free Tier** |
| **Total** | **1,2829** | **0,2134** | |

## Janela 3 contra o estimado

- **Linhas exclusivas do lab EKS** (plano de controle, NLB, EBS e outros do EC2): **US$ 0,52**.
- **Janela 3 inteira:** **~US$ 0,75 a 0,80**. É uma estimativa sobre o dado real, porque a parte da stack principal e dos IPv4 não se separa da janela 2 no mesmo dia: são ~5,3 h a ~US$ 0,04/h de stack, mais ~8 horas-IP dos nós.
- O estimado era ~US$ 0,90 a 1,00, com teto de US$ 1,5. A diferença principal: **os nós não custaram nada** (Free Tier), e eu tinha contado ~US$ 0,17 para eles.
- **Teste de ponta a ponta do `infra.yml`:** ~20 min de stack, dentro dos US$ 0,21 parciais de 15/10. O valor exato não se separa do fim da janela 3.

## Limites

- Dados estimados pela AWS. O 15/10 ainda está aberto.
- A divisão entre janela 2 e janela 3 dentro de 14/10 é uma estimativa. Só os serviços exclusivos do lab (EKS, ELB, EBS) são atribuíveis com certeza.
- O motivo dos ~US$ 20 de crédito a mais não foi conferido.
