# ADR 0002: VPC Link V2 com Cloud Map e registro SRV

## Contexto

- Sem ALB, o API Gateway precisa de outra forma de achar as tasks. A integração privada com Cloud Map usa a chamada `DiscoverInstances`, e o ECS precisa registrar as tasks com registro SRV (service discovery) ou usar Service Connect. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Fatos de serviços AWS"]
- O nome do serviço não resolve por registro A. [FATO: [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md) seção "Portas e fluxo de rede"]
- O VPC Link V2 é imutável (subnets e SGs) e fica INACTIVE após 60 dias sem tráfego. [FATO: [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md) seção "Fatos de serviços AWS"]
- No código, o serviço Cloud Map tem registro `SRV`, política `MULTIVALUE` e TTL de 10 s (`[PROPOSTA] a calibrar`). [FATO: [`modules/cloudmap/main.tf`](../../infrastructure/modules/cloudmap/main.tf) linhas 10-24 e [`variables.tf`](../../infrastructure/modules/cloudmap/variables.tf) linhas 16-20]
- O ECS registra as tasks por `service_registries` com `registry_arn`, `container_name` e `container_port`. [FATO: [`modules/ecs/main.tf`](../../infrastructure/modules/ecs/main.tf) linhas 97-105]
- A integração do API Gateway usa o ARN do serviço Cloud Map como `integration_uri`, e o VPC Link fica nas subnets privadas com o SG `vpclink`. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 335-346 e [`modules/apigw/main.tf`](../../infrastructure/modules/apigw/main.tf) linhas 9-24]
- A zona privada do Route 53 do namespace exige `enable_dns_support` e `enable_dns_hostnames` na VPC. [FATO: [`modules/network/vpc/main.tf`](../../infrastructure/modules/network/vpc/main.tf) linhas 4-5]
- Preços: Cloud Map a US$ 0,10 por recurso registrado por mês e US$ 1,00 por milhão de chamadas de descoberta; zona privada do Route 53 a US$ 0,50/mês. [FATO: [`02-finops-guardrails.md`](../../.kiro/steering/02-finops-guardrails.md) seção "Preços de referência", fonte aws.amazon.com/cloud-map/pricing]

## Decisão

Usar VPC Link V2 nas subnets privadas, com um namespace privado do Cloud Map e um serviço com registro SRV. O ECS registra e remove as tasks sozinho. O VPC Link é definido uma única vez, porque mudar subnets ou SGs recria o link.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| ALB ou NLB atrás do VPC Link | Custo fixo por hora, **a verificar** | Reintroduz o custo fixo que o [ADR 0001](0001-api-gateway-http-api-no-lugar-de-alb.md) evita |
| ECS Service Connect | **A verificar** | Citado na doc como alternativa de registro. Não foi avaliado neste projeto |
| Registro A no Cloud Map | Igual ao SRV | Não funciona com a integração do API Gateway |

## Consequências

- O k6 não resolve SRV. Os testes dentro da VPC buscam os IPs das tasks com `aws servicediscovery discover-instances` e distribuem as requisições. [FATO: [`08-testes-de-carga.md`](../../.kiro/steering/08-testes-de-carga.md) seção "Perfis"]
- Mudar subnets ou SGs do VPC Link recria o link e a integração. Todo `plan` que mostre essa recriação é revisado antes do apply. [FATO: [`modules/apigw/main.tf`](../../infrastructure/modules/apigw/main.tf) linhas 7-8]
- Se a stack ficar 60 dias sem tráfego, o VPC Link fica INACTIVE. Na prática a stack é destruída após cada janela de avaliação, então o risco é baixo. [HIPÓTESE: depende de a janela de uso respeitar esse prazo]
- Não se sabe se o API Gateway faz cache do `DiscoverInstances`. Isso muda o custo por requisição (de US$ 1 para até US$ 2 por milhão). [FATO: lista "DESCONHECIDO" em [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md)]
- O `destroy` usa `force_destroy = true` no serviço Cloud Map, porque o deregister das tasks pelo ECS é assíncrono. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 206-214]
- O registro, a descoberta e o roteamento por VPC Link ainda não foram exercitados na AWS.

## Status

Aceito. Decisão travada em [`01-arquitetura-e-restricoes.md`](../../.kiro/steering/01-arquitetura-e-restricoes.md). Implementada no código, não aplicada na AWS.
