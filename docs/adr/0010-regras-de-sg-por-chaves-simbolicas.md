# ADR 0010: Regras de SG por chaves simbólicas em vez de `templatefile()`

## Contexto

- O repositório base descrevia as regras dos SGs em JSON com placeholders como `${ALB_SG_ID}`, resolvidos com `templatefile()`. [FATO: F-INF-4 em [`00-fonte-da-verdade.md`](../../.kiro/steering/00-fonte-da-verdade.md)]
- Os três SGs da trilha referenciam uns aos outros: VPC Link para tasks, tasks para RDS e RDS a partir das tasks. Com regras inline (`ingress` e `egress` dentro do `aws_security_group`) o Terraform não encontra ordem de criação: o grafo tem ciclo.
- Na análise de design de 12/10/2026 (artefato local, fora do repositório), os cenários foram reproduzidos com `hashicorp/aws` 6.68.0:
  - Três SGs com regras inline cruzadas: `terraform validate` e `plan` falham com `Error: Cycle`.
  - O módulo original instanciado três vezes, referenciando os outros por `security_groups`: o mesmo ciclo.
  - SGs vazios mais `jsondecode(templatefile(...))` com o ID do SG como chave do `for_each`: o `validate` passa, o `plan` falha com `Invalid for_each argument ... will be known only after apply`, porque o ID do SG só existe depois do apply.
  - Módulo novo, regras por chave simbólica e mapa `sg_ids`: `validate` limpo e `plan` com 11 recursos a criar (1 VPC, 3 SGs, 7 regras).
  [HIPÓTESE: os resultados dos cenários com ciclo e com `templatefile` vêm da análise citada, que não está versionada, e não foram reproduzidos neste turno. O que está versionado e roda no CI cobre o modelo escolhido: [`tests/s3.tftest.hcl`](../../infrastructure/modules/security/security-group/tests/s3.tftest.hcl) prova que três instâncias com o mesmo `sg_ids` não formam ciclo, e [`tests/negativos.tftest.hcl`](../../infrastructure/modules/security/security-group/tests/negativos.tftest.hcl) cobre `sg_ref` inexistente, `rule_key` duplicado, dois tipos de origem, ingress aberto e porta ausente]
- A regra 9 de [`04-terraform.md`](../../.kiro/steering/04-terraform.md) foi ajustada para este modelo. A mudança entrou no commit `1583598`.
- Implementação: o SG nasce só com `name`, `description`, `vpc_id` e `tags`. As regras são recursos `aws_vpc_security_group_ingress_rule` e `aws_vpc_security_group_egress_rule`, com `for_each` por chave estática `<rule_key>/cidr4|cidr6|sg|self/<alvo>`. O ID do SG de origem ou destino entra só no valor, via `var.sg_ids[ref]`. [FATO: [`modules/security/security-group/main.tf`](../../infrastructure/modules/security/security-group/main.tf) linhas 1-78]
- A raiz passa o mesmo mapa `sg_ids` (`vpclink`, `ecs`, `rds`) aos três módulos, e os JSON são lidos com `jsondecode(file(...))`. [FATO: [`main.tf`](../../infrastructure/main.tf) linhas 44-55 (leitura dos JSON e mapa `sg_ids`) e 147-183]
- Validações no módulo: `rule_key` único por direção, exatamente um tipo de origem ou destino por regra, portas obrigatórias quando o protocolo não é `-1` e ingress sem `0.0.0.0/0` nem `::/0`. Uma `precondition` confere que cada `sg_ref` existe em `sg_ids`. [FATO: [`modules/security/security-group/variables.tf`](../../infrastructure/modules/security/security-group/variables.tf) linhas 43-66 e [`main.tf`](../../infrastructure/modules/security/security-group/main.tf) linhas 48-53]

## Decisão

Descrever as regras de SG em JSON com chaves simbólicas (`rule_key`, `sg_refs`), resolvidas pelo módulo `security-group` a partir de um mapa `sg_ids`. O ID do SG entra só no valor do atributo da regra, nunca na chave do `for_each`. `templatefile()` só vale para valores já conhecidos no plan.

## Alternativas consideradas

| Alternativa | Custo | Motivo da recusa |
|---|---|---|
| Regras inline nos três SGs | Sem custo | Ciclo no grafo, sem saída |
| `templatefile()` com `${INGRESS_SG_ID}` e `for_each` sobre o resultado | Sem custo | O ID do SG é desconhecido no plan, e o `for_each` falha |
| SGs vazios no módulo e regras na raiz | Sem custo | Espalha o contrato por duas camadas |
| Manter `templatefile()` passando uma string simbólica no lugar do ID | Sem custo | Funcionaria, mas um placeholder chamado `..._ID` que carrega uma chave engana quem lê |

## Consequências

- Mudar `name`, `description` ou `vpc_id` de um SG recria o SG e, em cascata, as regras e o VPC Link V2 (imutável) e o service. Todo `plan` com SG "must be replaced" é revisado antes do apply. [FATO: [`04-terraform.md`](../../.kiro/steering/04-terraform.md) regra 13]
- O módulo não pode ler `var.sg_ids` em nenhum atributo do `aws_security_group`, senão os três módulos voltam a formar ciclo. É uma restrição de manutenção do módulo. [FATO: comentário em [`modules/security/security-group/main.tf`](../../infrastructure/modules/security/security-group/main.tf) linhas 1-4]
- O egress padrão "permitir tudo" é removido pelo provider. Se faltar uma regra necessária (443, 53 ou 5432), a task não sobe. A tabela de portas é o roteiro de aceite. Ver [`docs/arquitetura.md`](../arquitetura.md).
- Duas regras com `rule_key` diferente e mesmos parâmetros resultariam em erro do EC2 (`InvalidPermission.Duplicate`) no apply. [HIPÓTESE: não testado contra a AWS]
- Não se sabe se mudar só a `description` de uma regra existente é update in-place ou replace. Verificar no primeiro `plan` com state.
- A cota de regras por SG é 60 para entrada e 60 para saída, e o maior SG da trilha (`ecs`) tem 4 regras de saída. [FATO: consulta de Service Quotas na análise de design citada acima, não repetida neste turno]
- O mesmo padrão foi aplicado às rotas: o repositório base usava o placeholder `${IGW_ID}` em `public.json`, e o código atual usa `gateway_ref: "igw"` mais `ref_ids = { igw = ... }` na chamada do módulo `route`. [FATO: [`config/routes/public.json`](../../infrastructure/config/routes/public.json) e [`main.tf`](../../infrastructure/main.tf) linhas 112-119]

## Status

Aceito. Implementado e coberto por testes de módulo (`terraform test`). Não aplicado na AWS.
