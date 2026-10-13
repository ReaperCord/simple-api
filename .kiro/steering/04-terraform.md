---
inclusion: fileMatch
fileMatchPattern: ["infrastructure/**/*.tf", "infrastructure/**/*.tfvars", "infrastructure/config/**"]
---

# Padrões de Terraform

## Regras

1. **Reaproveite os módulos existentes** em `infrastructure/modules/`. Corrija-os; não os substitua por módulos da Registry sem pedido.
2. **Não instancie** `nat-gateway`, `alb`, `target-group`, `listener` nem a rota de `config/routes/private.json` na trilha principal (ver `01-arquitetura-e-restricoes.md`).
3. Módulos novos (ecr, rds, apigw, cloudmap, autoscaling, oidc, budget) seguem o padrão do repo: `main.tf`, `variables.tf` (com `description` e `type`), `outputs.tf`.
4. Roots separados: `infrastructure/bootstrap/` (bucket de state, provider OIDC do GitHub, roles do pipeline, budget com `include_credit = false`, repositório ECR — aplicado uma vez, local, com `Track=bootstrap`), `infrastructure/` (stack principal), `infrastructure/eks-lab/`. A primeira imagem é publicada entre o bootstrap e a stack (ver `06-cicd.md`).
5. Bloco `terraform {}` com `required_version >= 1.11` e `required_providers` com versão fixada (`~>`). Confira a versão no Registry antes de escrever — não chute.
6. Provider com `default_tags` (ver `02-finops-guardrails.md`).
7. Nada de AZ, região, account ID ou ARN hardcoded. Use `var.region`, `data.aws_availability_zones`, `data.aws_caller_identity`. Corrigir o default de `azs` do módulo `route-table` (F-INF-7).
8. VPC com `enable_dns_hostnames = true` e `enable_dns_support = true` (F-INF-9). Subnet module passando a usar `map_public_ip_on_launch` (true nas públicas — F-INF-8).
9. Regras de SG em `config/security_rules/*.json` usam chaves simbólicas (`rule_key`, `sg_refs`) e NÃO IDs. O módulo `security-group` recebe o mapa `sg_ids` (chave simbólica → ID) e resolve o ID no atributo da regra, nunca na chave do `for_each`. `templatefile()` só vale para valores já conhecidos no plan.
10. Variáveis e outputs sensíveis: `sensitive = true`.
11. Task definition: o Terraform cria a revisão inicial; o pipeline publica as seguintes. No service, `lifecycle { ignore_changes = [task_definition, desired_count] }`. DOCUMENTE o trade-off (mudança de env var via Terraform não faz deploy sozinha).
12. ECS service: `deployment_circuit_breaker { enable = true, rollback = true }`; `service_registries` com `registry_arn`, `container_name` e `container_port` (registro SRV — exigido pela integração do API Gateway); `healthCheck` do container na task definition.
13. VPC Link V2 é imutável: mudar subnets/SGs recria o link. Defina-os uma vez e avise antes de um plan que o substitua.
14. RDS: `publicly_accessible = false`, `storage_encrypted = true`, `backup_retention_period = 7`, `manage_master_user_password = true`, `deletion_protection` e `skip_final_snapshot` explícitos (decisão documentada). Chave KMS padrão (sem custo); DR em outra conta exigiria chave gerenciada pelo cliente (~US$ 1/mês), porque snapshot com a chave padrão não pode ser compartilhado — documentado, não implementado.
15. API Gateway: estágio `$default` com throttling; integração do ECS com `overwrite:path` = `$request.path` (em integração privada o nome do estágio iria no caminho do backend).

## Anti-alucinação específica de Terraform

- Todo argumento que você escrever precisa existir na versão fixada do provider. Em dúvida: `terraform validate` e, se preciso, `terraform providers schema -json | jq '.provider_schemas["registry.terraform.io/hashicorp/aws"].resource_schemas["<tipo>"]'`.
- Não invente atributos de output (`.id` vs `.arn` vs `.name`). Confira na doc do recurso.
- Não declare que algo "funciona" sem `terraform validate` limpo e, quando houver credencial de leitura, `terraform plan`.

## Comandos permitidos sem aprovação

`terraform fmt -recursive`, `terraform init -backend=false`, `terraform validate`, `terraform plan -lock=false` (com o perfil read-only: a trava nativa do S3 precisa gravar o objeto `.tflock`, o que esse perfil não pode), `trivy config infrastructure/`, `tflint`.

## Comandos que exigem aprovação explícita no turno (e um perfil de escrita que só o Leandro ativa)

`terraform apply`, `terraform destroy`, `terraform import`.

## Proibidos para o agente (bloqueados nas permissões)

`-auto-approve`, `terraform init -migrate-state`, `terraform state rm|mv|pull|push`, `terraform force-unlock`, `terraform console`, `terraform show -json`, `terraform output -json|-raw` (expõem valores sensíveis ou mexem no state). Se forem necessários, o Leandro roda.

## Ordem de composição da raiz

`vpc → subnets → igw → route tables/rotas (só públicas com IGW) → security groups → rds → cloud map → ecs (task def com a imagem já publicada no ECR do bootstrap + service) → apigw (vpc link + integração + rotas + estágio $default com throttling) → autoscaling → alarmes → outputs`
