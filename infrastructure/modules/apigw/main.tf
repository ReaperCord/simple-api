resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"
  tags          = var.tags
}

# Regra 13 (04-terraform.md): o VPC Link V2 e imutavel. Mudar subnet_ids ou security_group_ids
# RECRIA o link (e a integracao). Defina-os uma vez e avise antes de um plan que o substitua.
resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${var.name}-vpclink"
  subnet_ids         = var.vpc_link_subnet_ids
  security_group_ids = var.vpc_link_security_group_ids
  tags               = var.tags
}

resource "aws_apigatewayv2_integration" "this" {
  api_id             = aws_apigatewayv2_api.this.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.this.id

  # Em integracao privada com Cloud Map, o URI e o ARN do servico (registro SRV).
  integration_uri = var.integration_uri

  # Em integracao privada o nome do estagio iria no caminho enviado ao backend; sobrescrevemos
  # com o caminho original (01-arquitetura-e-restricoes.md).
  request_parameters = {
    "overwrite:path" = "$request.path"
  }
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags

  default_route_settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }
}
