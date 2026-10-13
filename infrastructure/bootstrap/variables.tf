variable "project_name" {
  description = "Nome do projeto (tag Project e prefixo dos recursos)"
  type        = string
  default     = "simple-api"
}

variable "environment" {
  description = "Ambiente alvo dos nomes de ECS e IAM que os pipelines podem operar (tag Env); o state e as roles do bootstrap sao unicos"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "hml", "prod"], var.environment)
    error_message = "environment deve ser dev, hml ou prod."
  }
}

variable "region" {
  description = "Regiao AWS do bootstrap; sem default, vem do tfvars"
  type        = string
}

variable "owner" {
  description = "Valor da tag Owner"
  type        = string
  default     = "leandro"
}

variable "ttl" {
  description = "Valor da tag TTL (data ISO ou none); o bootstrap e permanente"
  type        = string
  default     = "none"
}

variable "github_owner" {
  description = "Dono (usuario ou organizacao) do repositorio GitHub; sem default (placeholder <GITHUB_OWNER> no exemplo)"
  type        = string
}

variable "github_repo" {
  description = "Nome do repositorio GitHub"
  type        = string
  default     = "simple-api"
}

variable "github_owner_id" {
  description = "ID numerico do dono do repositorio (claim repository_owner_id); compoe o sub imutavel do OIDC. Publico na API do GitHub, sem default"
  type        = string
}

variable "github_repo_id" {
  description = "ID numerico do repositorio (claim repository_id); compoe o sub imutavel do OIDC. Publico na API do GitHub, sem default"
  type        = string
}

variable "budget_emails" {
  description = "E-mails que recebem os alertas do AWS Budgets; sem default para nao versionar PII (placeholder <EMAIL> no exemplo)"
  type        = list(string)
  sensitive   = true
}

variable "budget_limit_amount" {
  description = "Limite mensal do budget em USD (meta de 02-finops-guardrails.md)"
  type        = string
  default     = "45"
}

variable "ecr_repository_name" {
  description = "Nome do repositorio ECR; vazio usa o project_name"
  type        = string
  default     = ""
}

variable "ecr_max_image_count" {
  description = "[PROPOSTA] a calibrar: quantidade de imagens mantidas no ECR pela lifecycle policy"
  type        = number
  default     = 10
}
