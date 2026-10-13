variable "role_name" {
  description = "Nome da IAM Role (a policy anexada recebe o sufixo -policy)"
  type        = string
}

variable "assume_role_policy_json" {
  description = "JSON da trust policy (assume role policy) da role"
  type        = string
}

variable "policy_json" {
  description = "JSON da policy de permissoes (menor privilegio) anexada a role"
  type        = string
}

variable "tags" {
  description = "Tags aplicadas a role e a policy"
  type        = map(string)
  default     = {}
}
