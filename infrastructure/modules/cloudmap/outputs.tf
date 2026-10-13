output "namespace_id" {
  description = "ID do namespace DNS privado"
  value       = aws_service_discovery_private_dns_namespace.this.id
}

output "service_arn" {
  description = "ARN do servico Cloud Map (registry_arn do ECS e integration_uri do API Gateway)"
  value       = aws_service_discovery_service.this.arn
}

output "service_id" {
  description = "ID do servico Cloud Map"
  value       = aws_service_discovery_service.this.id
}
