resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.namespace_name
  description = "Namespace privado ${var.namespace_name}"
  vpc         = var.vpc_id
  tags        = var.tags
}

# Registro SRV (exigido pela integracao do API Gateway via VPC Link V2): o nome do servico
# nao resolve por registro A. O ECS registra e remove as tasks sozinho (service_registries).
resource "aws_service_discovery_service" "this" {
  name          = var.service_name
  description   = "Servico ${var.service_name} (registro SRV)"
  force_destroy = var.force_destroy
  tags          = var.tags

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.this.id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "SRV"
      ttl  = var.dns_ttl
    }
  }
}
