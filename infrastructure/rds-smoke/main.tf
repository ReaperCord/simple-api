# Teste barato de RDS (Forma 2): root efemero, state LOCAL. Prova que o Free plan desta conta
# deixa CRIAR um RDS db.t4g.micro antes de comprometer a stack inteira (~US$ 34/mes).
# Reaproveita os MESMOS modulos da stack principal (vpc, subnet, security-group, rds), sem copiar.
# Nada de ECS, Cloud Map, API Gateway, IGW nem IP publico: so VPC + 2 subnets privadas + SG + RDS.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnet_names = ["rds-smoke-private-1a", "rds-smoke-private-1b"]
}

module "vpc" {
  source = "../modules/network/vpc"

  vpc_cidr_block = var.vpc_cidr_block
  tags           = { Name = "rds-smoke-vpc" }
}

# Subnets PRIVADAS (sem IGW, sem rota default): o RDS nao precisa de internet. 2 AZs pelo subnet group.
module "private_subnets" {
  source = "../modules/network/subnet"

  vpc_id                  = module.vpc.vpc_id
  subnet_name             = local.private_subnet_names
  subnet_cidr             = var.private_subnet_cidrs
  availability_zone       = local.azs
  map_public_ip_on_launch = false
  tags                    = { Name = "rds-smoke-private" }
}

# SG do RDS sem regras: o teste nao conecta no banco, so prova a CRIACAO. Sem ingress nenhum SG
# aceita trafego (default deny), o que e seguro de proposito.
module "sg_rds" {
  source = "../modules/security/security-group"

  name        = "rds-smoke-rds"
  description = "SG efemero do RDS de teste (sem regras: so prova a criacao)"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = "rds-smoke-rds" }
}

module "rds" {
  source = "../modules/rds"

  identifier              = "rds-smoke"
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  db_name                 = "simple_api"
  master_username         = "simple_api"
  allocated_storage       = var.db_allocated_storage
  backup_retention_period = var.backup_retention_period
  subnet_ids              = module.private_subnets.subnet_ids_ordered
  vpc_security_group_ids  = [module.sg_rds.security_group_id]

  # Efemero: sem protecao, sem snapshot final, destroy limpo e sem custo residual.
  deletion_protection = false
  skip_final_snapshot = true

  tags = { Name = "rds-smoke-db" }
}

output "db_instance_id" {
  description = "Identificador da instancia criada (prova do teste)"
  value       = module.rds.instance_id
}

output "db_endpoint" {
  description = "Endpoint do banco (nao e segredo; a senha fica no Secrets Manager gerenciada pelo RDS)"
  value       = module.rds.address
}
