# Depende SO de aws_security_group.this (nunca das regras): se dependesse, os 3 modulos
# que recebem o mesmo mapa sg_ids formariam um ciclo.
output "security_group_id" {
  description = "ID do security group"
  value       = aws_security_group.this.id
}
