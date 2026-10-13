variable "name" {
  description = "Nome da HTTP API (prefixo do nome do VPC Link)"
  type        = string
}

variable "vpc_link_subnet_ids" {
  description = "Subnets do VPC Link V2 (imutavel: mudar recria o link)"
  type        = list(string)
}

variable "vpc_link_security_group_ids" {
  description = "Security Groups do VPC Link V2 (imutavel: mudar recria o link)"
  type        = list(string)
}

variable "integration_uri" {
  description = "ARN do servico Cloud Map (registro SRV) alvo da integracao"
  type        = string
}

variable "throttling_rate_limit" {
  description = "Limite de requisicoes por segundo do estagio $default; sem default, o valor vem do tfvars ([PROPOSTA] a calibrar)"
  type        = number
}

variable "throttling_burst_limit" {
  description = "Limite de burst do estagio $default; sem default, o valor vem do tfvars ([PROPOSTA] a calibrar)"
  type        = number
}

variable "tags" {
  description = "Tags aplicadas a API, ao VPC Link e ao estagio"
  type        = map(string)
  default     = {}
}
