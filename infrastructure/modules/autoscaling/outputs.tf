output "resource_id" {
  description = "resource_id do scalable target (service/<cluster>/<service>)"
  value       = aws_appautoscaling_target.this.resource_id
}

output "policy_arn" {
  description = "ARN da policy de target tracking de CPU"
  value       = aws_appautoscaling_policy.cpu.arn
}
