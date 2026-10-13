output "address" {
  description = "Hostname do endpoint da instancia (DB_HOST da aplicacao)"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Porta do banco"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Nome do banco criado"
  value       = aws_db_instance.this.db_name
}

output "instance_id" {
  description = "Identificador da instancia (dimensao DBInstanceIdentifier do CloudWatch)"
  value       = aws_db_instance.this.identifier
}

output "master_user_secret_arn" {
  description = "ARN do segredo (Secrets Manager) com a senha master gerenciada pelo RDS; e um ARN, nao o segredo"
  value       = one(aws_db_instance.this.master_user_secret[*].secret_arn)
}
