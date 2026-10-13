variable "cluster_name" {
  description = "Nome do cluster ECS"
  type        = string
}

variable "service_name" {
  description = "Nome do service ECS"
  type        = string
}

variable "min_capacity" {
  description = "Numero minimo de tasks"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Numero maximo de tasks"
  type        = number
  default     = 3
}

variable "cpu_target_value" {
  description = "Alvo de ECSServiceAverageCPUUtilization (%)"
  type        = number
  default     = 60
}

variable "scale_out_cooldown" {
  description = "Cooldown (s) apos um scale-out"
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Cooldown (s) apos um scale-in"
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags aplicadas ao scalable target"
  type        = map(string)
  default     = {}
}
