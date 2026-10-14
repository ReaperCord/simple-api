output "api_endpoint" {
  description = "URL base da API (HTTP API, estagio $default); usada no smoke test (vars.API_URL)"
  value       = module.apigw.api_endpoint
}

output "vpc_id" {
  description = "ID da VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas (tasks ECS)"
  value       = module.public_subnets.subnet_ids_ordered
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (RDS e VPC Link)"
  value       = module.private_subnets.subnet_ids_ordered
}

output "ecs_cluster_name" {
  description = "Nome do cluster ECS"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Nome do service ECS"
  value       = module.ecs.service_name
}

output "ecs_task_definition_arn" {
  description = "ARN da revisao inicial da task definition (o pipeline registra as seguintes)"
  value       = module.ecs.task_definition_arn
}

output "ecs_log_group_name" {
  description = "Log group da aplicacao"
  value       = module.ecs.log_group_name
}

output "execution_role_arn" {
  description = "ARN da role de execucao da task"
  value       = module.execution_role.role_arn
}

output "task_role_arn" {
  description = "ARN da role da aplicacao (GetSecretValue so no segredo do RDS)"
  value       = module.task_role.role_arn
}

output "rds_address" {
  description = "Hostname do RDS (privado)"
  value       = module.rds.address
}

output "rds_master_user_secret_arn" {
  description = "ARN do segredo da senha master (e um ARN, nao o segredo)"
  value       = module.rds.master_user_secret_arn
}

output "cloudmap_service_arn" {
  description = "ARN do servico Cloud Map (registro SRV)"
  value       = module.cloudmap.service_arn
}

output "db_init_task_definition_arn" {
  description = "ARN da task definition do db-init (so no modo IAM; rode com tools/run-db-init.sh depois do apply)"
  value       = one(aws_ecs_task_definition.dbinit[*].arn)
}

output "db_app_username" {
  description = "Usuario do banco usado pela app (modo IAM) ou null no modo senha"
  value       = var.db_iam_auth ? var.db_app_username : null
}

# Outputs lidos pelo root infrastructure/eks-lab via terraform_remote_state (nunca o contrario).
output "api_id" {
  description = "ID da HTTP API (a rota /eks do lab EKS entra nesta mesma API)"
  value       = module.apigw.api_id
}

output "vpc_link_id" {
  description = "ID do VPC Link V2 (compartilhado com o lab EKS)"
  value       = module.apigw.vpc_link_id
}

output "vpclink_security_group_id" {
  description = "SG do VPC Link V2 (o lab EKS acrescenta a regra de saida para o NLB)"
  value       = module.sg_vpclink.security_group_id
}

output "rds_security_group_id" {
  description = "SG do RDS (o lab EKS acrescenta uma regra de entrada 5432 a partir do SG do cluster, so enquanto o lab existir)"
  value       = module.sg_rds.security_group_id
}

output "rds_resource_id" {
  description = "DbiResourceId do RDS (ARN rds-db:connect do Pod Identity do lab EKS)"
  value       = module.rds.resource_id
}

output "rds_port" {
  description = "Porta do banco"
  value       = module.rds.port
}

output "rds_db_name" {
  description = "Nome do banco"
  value       = module.rds.db_name
}

