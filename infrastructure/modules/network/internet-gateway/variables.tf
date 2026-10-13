variable "tags" {
  description = "Tags adicionais para o Internet Gateway"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "ID da VPC onde o Internet Gateway será anexado"
  type        = string
}
