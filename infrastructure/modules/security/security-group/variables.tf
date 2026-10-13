variable "name" {
  description = "Nome do Security Group (ForceNew: nao mudar depois de criado)"
  type        = string
}

variable "description" {
  description = "Descrição do Security Group (ForceNew: nao mudar depois de criado)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde o SG será criado (ForceNew)"
  type        = string
}

variable "tags" {
  description = "Tags do SG e das regras"
  type        = map(string)
  default     = {}
}

variable "sg_ids" {
  description = "Mapa chave simbolica => ID de SG (ex: vpclink, ecs, rds), igual para todas as instancias do modulo. As CHAVES precisam ser conhecidas no plan; os IDs podem ser desconhecidos."
  type        = map(string)
  default     = {}
}

variable "ingress_rules" {
  description = "Regras de entrada. rule_key e unico na lista; informe exatamente um entre cidr_blocks, ipv6_cidr_blocks, sg_refs (chaves de sg_ids = origem) ou self. protocol '-1' dispensa portas. Ingress nao aceita 0.0.0.0/0 nem ::/0."
  type = list(object({
    rule_key         = string
    description      = string
    protocol         = string
    from_port        = optional(number)
    to_port          = optional(number)
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
    sg_refs          = optional(list(string), [])
    self             = optional(bool, false)
  }))
  default = []

  validation {
    condition     = length(distinct([for r in var.ingress_rules : r.rule_key])) == length(var.ingress_rules)
    error_message = "ingress_rules: rule_key duplicado (o merge do for_each sobrescreveria a regra em silencio)."
  }

  validation {
    condition = alltrue([
      for r in var.ingress_rules :
      (length(r.cidr_blocks) > 0 ? 1 : 0) + (length(r.ipv6_cidr_blocks) > 0 ? 1 : 0) + (length(r.sg_refs) > 0 ? 1 : 0) + (r.self ? 1 : 0) == 1
    ])
    error_message = "ingress_rules: cada regra precisa de exatamente UM tipo de origem (cidr_blocks, ipv6_cidr_blocks, sg_refs ou self)."
  }

  validation {
    condition     = alltrue([for r in var.ingress_rules : r.protocol == "-1" || (r.from_port != null && r.to_port != null)])
    error_message = "ingress_rules: from_port e to_port sao obrigatorios quando protocol != '-1'."
  }

  validation {
    condition = alltrue([
      for r in var.ingress_rules :
      !contains(r.cidr_blocks, "0.0.0.0/0") && !contains(r.ipv6_cidr_blocks, "::/0")
    ])
    error_message = "ingress_rules: ingress aberto para 0.0.0.0/0 ou ::/0 nao e permitido (03-devsecops.md)."
  }
}

variable "egress_rules" {
  description = "Regras de saida. rule_key e unico na lista; informe exatamente um entre cidr_blocks, ipv6_cidr_blocks, sg_refs (chaves de sg_ids = destino) ou self. protocol '-1' dispensa portas."
  type = list(object({
    rule_key         = string
    description      = string
    protocol         = string
    from_port        = optional(number)
    to_port          = optional(number)
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
    sg_refs          = optional(list(string), [])
    self             = optional(bool, false)
  }))
  default = []

  validation {
    condition     = length(distinct([for r in var.egress_rules : r.rule_key])) == length(var.egress_rules)
    error_message = "egress_rules: rule_key duplicado (o merge do for_each sobrescreveria a regra em silencio)."
  }

  validation {
    condition = alltrue([
      for r in var.egress_rules :
      (length(r.cidr_blocks) > 0 ? 1 : 0) + (length(r.ipv6_cidr_blocks) > 0 ? 1 : 0) + (length(r.sg_refs) > 0 ? 1 : 0) + (r.self ? 1 : 0) == 1
    ])
    error_message = "egress_rules: cada regra precisa de exatamente UM tipo de destino (cidr_blocks, ipv6_cidr_blocks, sg_refs ou self)."
  }

  validation {
    condition     = alltrue([for r in var.egress_rules : r.protocol == "-1" || (r.from_port != null && r.to_port != null)])
    error_message = "egress_rules: from_port e to_port sao obrigatorios quando protocol != '-1'."
  }
}
