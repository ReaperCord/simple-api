variable "vpc_cidr_block" {
  description = "Subrede padrão do VPC"
  type        = string
}

variable "tags" {
  description = "Tags adicionais para a VPC"
  type        = map(string)
  default     = {}
}
