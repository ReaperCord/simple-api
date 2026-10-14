# ETAPA 2 (var.enable_api_route = true): as rotas do lab entram na MESMA HTTP API da stack principal, como recursos
# proprios deste root. So depois de o NLB existir (criado pelo AWS Load Balancer Controller a partir do Service).
# O prefixo /eks sai do caminho enviado ao pod por overwrite:path (em integracao privada o API Gateway repassaria o
# caminho completo). O formato exato do mapeamento NAO tem exemplo na doc para integracao privada: testar na AWS.

data "aws_lb" "nlb" {
  count = var.enable_api_route ? 1 : 0

  tags = {
    "service.k8s.aws/stack" = var.nlb_service_stack
  }
}

data "aws_lb_listener" "nlb" {
  count = var.enable_api_route ? 1 : 0

  load_balancer_arn = data.aws_lb.nlb[0].arn
  port              = var.nlb_listener_port
}

# O VPC Link da stack principal so tem saida para as tasks ECS (3000): o lab acrescenta a saida para o NLB.
resource "aws_vpc_security_group_egress_rule" "vpclink_to_nlb" {
  count = var.enable_api_route ? 1 : 0

  security_group_id = local.main.vpclink_security_group_id
  cidr_ipv4         = data.aws_vpc.main.cidr_block
  from_port         = var.nlb_listener_port
  to_port           = var.nlb_listener_port
  ip_protocol       = "tcp"
  description       = "EKS lab (temporario): VPC Link ate o NLB interno"
}

resource "aws_apigatewayv2_integration" "eks_proxy" {
  count = var.enable_api_route ? 1 : 0

  api_id             = local.main.api_id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = local.main.vpc_link_id
  integration_uri    = data.aws_lb_listener.nlb[0].arn

  request_parameters = {
    "overwrite:path" = "/$request.path.proxy"
  }
}

resource "aws_apigatewayv2_integration" "eks_root" {
  count = var.enable_api_route ? 1 : 0

  api_id             = local.main.api_id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = local.main.vpc_link_id
  integration_uri    = data.aws_lb_listener.nlb[0].arn

  request_parameters = {
    "overwrite:path" = "/"
  }
}

resource "aws_apigatewayv2_route" "eks_proxy" {
  count = var.enable_api_route ? 1 : 0

  api_id    = local.main.api_id
  route_key = "ANY /eks/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.eks_proxy[0].id}"
}

resource "aws_apigatewayv2_route" "eks_root" {
  count = var.enable_api_route ? 1 : 0

  api_id    = local.main.api_id
  route_key = "ANY /eks"
  target    = "integrations/${aws_apigatewayv2_integration.eks_root[0].id}"
}
