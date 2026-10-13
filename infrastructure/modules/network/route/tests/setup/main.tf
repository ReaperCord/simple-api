# Harness do teste: o ID do IGW so existe no apply (desconhecido no plan) e entra no modulo
# route apenas como VALOR de ref_ids. O for_each usa as chaves estaticas do JSON.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
}

module "route" {
  source = "../.."

  route_table_id = aws_route_table.this.id
  routes_json    = file("${path.module}/public.json")
  ref_ids        = { igw = aws_internet_gateway.this.id }
}

output "route_ids" {
  description = "IDs das rotas criadas, por chave do JSON"
  value       = module.route.route_ids
}
