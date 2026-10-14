output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint publico da API do Kubernetes (autenticacao por IAM; nao e segredo)"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "SG do cluster (nos e pods)"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "app_role_arn" {
  description = "Role do Pod Identity da app (rds-db:connect so em app_connect)"
  value       = module.app_role.role_arn
}

output "lbc_role_arn" {
  description = "Role do Pod Identity do AWS Load Balancer Controller"
  value       = module.lbc_role.role_arn
}

output "db_host" {
  description = "Hostname do RDS da stack principal (alimenta o ConfigMap simple-api-db criado pelo workflow)"
  value       = local.main.rds_address
}

output "db_port" {
  description = "Porta do RDS"
  value       = local.main.rds_port
}

output "db_name" {
  description = "Nome do banco"
  value       = local.main.rds_db_name
}

output "db_app_username" {
  description = "Usuario do banco da app (modo IAM)"
  value       = var.db_app_username
}

output "ttl" {
  description = "Horario de expiracao do lab (UTC)"
  value       = var.ttl
}
