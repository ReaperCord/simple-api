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
