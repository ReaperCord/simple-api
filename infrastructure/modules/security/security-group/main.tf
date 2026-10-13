# Contrato (Decisao 1): o SG nasce so com name/description/vpc_id/tags e as regras sao recursos
# standalone. IDs de SG entram apenas no VALOR (var.sg_ids[ref]); as chaves do for_each sao
# estaticas ("<rule_key>/cidr4|cidr6|sg|self/..."). Nao leia var.sg_ids em nenhum atributo do
# aws_security_group, senao os 3 modulos formam ciclo entre si.
resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags        = var.tags
}

locals {
  ingress_flat = merge([
    for r in var.ingress_rules : merge(
      { for c in r.cidr_blocks : "${r.rule_key}/cidr4/${c}" => { rule = r, kind = "cidr4", target = c } },
      { for c in r.ipv6_cidr_blocks : "${r.rule_key}/cidr6/${c}" => { rule = r, kind = "cidr6", target = c } },
      { for s in r.sg_refs : "${r.rule_key}/sg/${s}" => { rule = r, kind = "sg", target = s } },
      r.self ? { "${r.rule_key}/self" = { rule = r, kind = "self", target = "self" } } : {}
    )
  ]...)

  egress_flat = merge([
    for r in var.egress_rules : merge(
      { for c in r.cidr_blocks : "${r.rule_key}/cidr4/${c}" => { rule = r, kind = "cidr4", target = c } },
      { for c in r.ipv6_cidr_blocks : "${r.rule_key}/cidr6/${c}" => { rule = r, kind = "cidr6", target = c } },
      { for s in r.sg_refs : "${r.rule_key}/sg/${s}" => { rule = r, kind = "sg", target = s } },
      r.self ? { "${r.rule_key}/self" = { rule = r, kind = "self", target = "self" } } : {}
    )
  ]...)
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_flat

  security_group_id = aws_security_group.this.id
  description       = each.value.rule.description
  ip_protocol       = each.value.rule.protocol
  from_port         = each.value.rule.protocol == "-1" ? null : each.value.rule.from_port
  to_port           = each.value.rule.protocol == "-1" ? null : each.value.rule.to_port
  cidr_ipv4         = each.value.kind == "cidr4" ? each.value.target : null
  cidr_ipv6         = each.value.kind == "cidr6" ? each.value.target : null
  referenced_security_group_id = (
    each.value.kind == "sg" ? var.sg_ids[each.value.target] :
    each.value.kind == "self" ? aws_security_group.this.id : null
  )
  tags = var.tags

  lifecycle {
    precondition {
      condition     = each.value.kind != "sg" || contains(keys(var.sg_ids), each.value.target)
      error_message = "Regra '${each.key}': sg_ref '${each.value.target}' nao existe em sg_ids (chaves validas: ${join(", ", keys(var.sg_ids))})."
    }
  }
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.egress_flat

  security_group_id = aws_security_group.this.id
  description       = each.value.rule.description
  ip_protocol       = each.value.rule.protocol
  from_port         = each.value.rule.protocol == "-1" ? null : each.value.rule.from_port
  to_port           = each.value.rule.protocol == "-1" ? null : each.value.rule.to_port
  cidr_ipv4         = each.value.kind == "cidr4" ? each.value.target : null
  cidr_ipv6         = each.value.kind == "cidr6" ? each.value.target : null
  referenced_security_group_id = (
    each.value.kind == "sg" ? var.sg_ids[each.value.target] :
    each.value.kind == "self" ? aws_security_group.this.id : null
  )
  tags = var.tags

  lifecycle {
    precondition {
      condition     = each.value.kind != "sg" || contains(keys(var.sg_ids), each.value.target)
      error_message = "Regra '${each.key}': sg_ref '${each.value.target}' nao existe em sg_ids (chaves validas: ${join(", ", keys(var.sg_ids))})."
    }
  }
}
