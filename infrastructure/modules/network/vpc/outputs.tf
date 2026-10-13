output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "Bloco CIDR da VPC"
  value       = aws_vpc.this.cidr_block
}

output "vpc_arn" {
  description = "ARN da VPC"
  value       = aws_vpc.this.arn
}
