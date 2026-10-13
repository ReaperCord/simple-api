variable "namespace_name" {
  description = "Nome do namespace DNS privado (ex: dev.simple-api.local)"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC associada ao namespace (precisa de enable_dns_support e enable_dns_hostnames)"
  type        = string
}

variable "service_name" {
  description = "Nome do servico registrado no namespace"
  type        = string
}

variable "dns_ttl" {
  description = "[PROPOSTA] a calibrar: TTL em segundos do registro SRV"
  type        = number
  default     = 10
}

variable "force_destroy" {
  description = "Se true, o destroy remove o servico mesmo com instancias ainda registradas (o deregister do ECS e assincrono)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags aplicadas ao namespace e ao servico"
  type        = map(string)
  default     = {}
}
