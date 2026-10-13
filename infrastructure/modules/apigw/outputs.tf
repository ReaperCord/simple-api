output "api_endpoint" {
  description = "URL base da HTTP API (estagio $default, sem prefixo de estagio)"
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_id" {
  description = "ID da HTTP API (dimensao ApiId do CloudWatch)"
  value       = aws_apigatewayv2_api.this.id
}

output "vpc_link_id" {
  description = "ID do VPC Link V2"
  value       = aws_apigatewayv2_vpc_link.this.id
}

output "stage_name" {
  description = "Nome do estagio (dimensao Stage do CloudWatch)"
  value       = aws_apigatewayv2_stage.default.name
}
