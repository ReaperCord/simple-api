variable "github_owner" {
  description = "Dono (usuario ou organizacao) do repositorio GitHub; sem default para nao fixar o dono no codigo"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.github_owner))
    error_message = "github_owner so aceita letras, numeros e hifen (sem curingas: ele compoe o sub exato do token OIDC)."
  }
}

variable "github_repo" {
  description = "Nome do repositorio GitHub; sem default"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo so aceita letras, numeros, ponto, underscore e hifen (sem curingas: ele compoe o sub exato do token OIDC)."
  }
}

variable "project_name" {
  description = "Prefixo dos recursos do projeto; limita o IAM do gha-infra a role/<project>-* e policy/<project>-*"
  type        = string
}

variable "region" {
  description = "Regiao permitida (aws:RequestedRegion) para as acoes regionais do gha-infra e dos ARNs construidos"
  type        = string
}

variable "state_bucket_name" {
  description = "Nome do bucket S3 do state remoto da stack principal"
  type        = string
}

variable "state_key" {
  description = "Chave do objeto de state da stack principal no bucket; o lock nativo grava <key>.tflock"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN do repositorio ECR do projeto (push do gha-deploy; leitura do gha-plan e do gha-infra)"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Nome do cluster ECS da stack principal (ARN do service do gha-deploy)"
  type        = string
}

variable "ecs_service_name" {
  description = "Nome do service ECS da stack principal (ARN do service do gha-deploy)"
  type        = string
}

variable "task_role_names" {
  description = "Nomes das 2 roles da task ECS (execucao e aplicacao) que o gha-deploy pode passar com iam:PassRole"
  type        = list(string)

  validation {
    condition     = length(var.task_role_names) == 2
    error_message = "Informe exatamente as 2 roles da task (execucao e aplicacao)."
  }
}

variable "tags" {
  description = "Tags aplicadas ao provider OIDC e as roles"
  type        = map(string)
  default     = {}
}
