# Harness do teste S3 (Decisao 1): VPC + 3 instancias do modulo recebendo o MESMO mapa sg_ids
# (inclusive a referencia ao proprio modulo), com as regras REAIS de config/security_rules.
# Esperado no plan: 1 VPC + 3 SGs + 7 regras = 11 recursos, sem Cycle.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {
  rules_dir = "${path.module}/../../../../../config/security_rules"

  sg_ids = {
    vpclink = module.sg_vpclink.security_group_id
    ecs     = module.sg_ecs.security_group_id
    rds     = module.sg_rds.security_group_id
  }

  r_vpclink = jsondecode(file("${local.rules_dir}/rules-sg-vpclink.json"))
  r_ecs     = jsondecode(file("${local.rules_dir}/rules-sg-ecs.json"))
  r_rds     = jsondecode(file("${local.rules_dir}/rules-sg-rds.json"))
}

resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

module "sg_vpclink" {
  source = "../.."

  name          = "test-vpclink"
  description   = "VPC Link"
  vpc_id        = aws_vpc.this.id
  sg_ids        = local.sg_ids
  ingress_rules = local.r_vpclink.ingress
  egress_rules  = local.r_vpclink.egress
}

module "sg_ecs" {
  source = "../.."

  name          = "test-ecs"
  description   = "ECS tasks"
  vpc_id        = aws_vpc.this.id
  sg_ids        = local.sg_ids
  ingress_rules = local.r_ecs.ingress
  egress_rules  = local.r_ecs.egress
}

module "sg_rds" {
  source = "../.."

  name          = "test-rds"
  description   = "RDS"
  vpc_id        = aws_vpc.this.id
  sg_ids        = local.sg_ids
  ingress_rules = local.r_rds.ingress
  egress_rules  = local.r_rds.egress
}

output "sg_keys" {
  description = "Chaves simbolicas do mapa sg_ids compartilhado"
  value       = keys(local.sg_ids)
}
