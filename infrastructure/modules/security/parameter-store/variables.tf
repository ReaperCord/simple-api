variable "name" {
  description = "Nome completo do parâmetro no SSM Parameter Store"
  type        = string
}

variable "description" {
  description = "Descrição do parâmetro"
  type        = string
}

variable "type" {
  description = "Tipo do parâmetro (String, SecureString ou StringList)"
  type        = string
  default     = "String"
}

variable "value" {
  description = "Valor do parâmetro (somente configuracao nao secreta)"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags aplicadas ao parâmetro"
  type        = map(string)
  default     = {}
}

