variable "vpc_id" {
  description = "ID da VPC onde as route tables serão criadas"
  type        = string
}

variable "subnet_ids" {
  description = "Lista com as subnets (em ordem); uma route table é criada por subnet"
  type        = list(string)
}

variable "tags" {
  description = "Tags aplicadas às route tables"
  type        = map(string)
  default     = {}
}
