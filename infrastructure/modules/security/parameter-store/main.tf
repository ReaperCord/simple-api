# Uso: SOMENTE configuracao NAO secreta. A senha do RDS vem do Secrets Manager
# (manage_master_user_password), nunca deste modulo.
resource "aws_ssm_parameter" "this" {
  name        = var.name
  description = var.description
  type        = var.type
  value       = var.value
  tags        = var.tags
}
