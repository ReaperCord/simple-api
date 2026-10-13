output "repository_url" {
  description = "URL do repositorio ECR (sem tag)"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN do repositorio ECR"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Nome do repositorio ECR"
  value       = aws_ecr_repository.this.name
}
