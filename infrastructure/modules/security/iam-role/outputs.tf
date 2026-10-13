output "role_arn" {
  description = "ARN da IAM Role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Nome da IAM Role"
  value       = aws_iam_role.this.name
}

output "role_id" {
  description = "ID da IAM Role"
  value       = aws_iam_role.this.id
}
