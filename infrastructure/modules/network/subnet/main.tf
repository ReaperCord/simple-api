locals {
  subnets = {
    for i, name in var.subnet_name : name => {
      cidr = element(var.subnet_cidr, i)
      az   = element(var.availability_zone, i)
    }
  }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = var.vpc_id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, {
    Name = each.key
  })
}
