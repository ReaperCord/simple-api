variable "repository_name" {
  description = "Nome do repositorio ECR"
  type        = string
}

variable "force_delete" {
  description = "Se true, o destroy apaga o repositorio mesmo com imagens; false protege as imagens"
  type        = bool
  default     = false
}

variable "max_image_count" {
  description = "[PROPOSTA] a calibrar: quantidade de imagens mantidas pela lifecycle policy (as mais antigas expiram)"
  type        = number
  default     = 10

  validation {
    condition     = var.max_image_count >= 1
    error_message = "max_image_count deve ser pelo menos 1."
  }
}

variable "tags" {
  description = "Tags aplicadas ao repositorio"
  type        = map(string)
  default     = {}
}
