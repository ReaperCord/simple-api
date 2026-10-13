output "cluster_id" {
  description = "ID do cluster ECS"
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN do cluster ECS"
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Nome do cluster ECS"
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Nome do serviço ECS"
  value       = aws_ecs_service.this.name
}

output "service_id" {
  description = "ID do serviço ECS"
  value       = aws_ecs_service.this.id
}

output "service_arn" {
  description = "ARN do serviço ECS"
  value       = aws_ecs_service.this.arn
}

output "task_definition_arn" {
  description = "ARN da task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  description = "Nome do CloudWatch Log Group do serviço"
  value       = aws_cloudwatch_log_group.this.name
}
