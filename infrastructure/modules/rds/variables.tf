variable "identifier" {
  description = "Identificador da instancia RDS (tambem prefixo do subnet group)"
  type        = string
}

variable "engine_version" {
  description = "Versao do PostgreSQL (major, ex: 16); conferir as versoes disponiveis na regiao antes do apply"
  type        = string
}

variable "instance_class" {
  description = "Classe da instancia RDS"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Nome do banco criado na instancia (DB_DATABASE da aplicacao)"
  type        = string
}

variable "master_username" {
  description = "Usuario master do banco (a senha e gerenciada pelo RDS no Secrets Manager)"
  type        = string
}

variable "port" {
  description = "Porta do PostgreSQL"
  type        = number
  default     = 5432
}

variable "allocated_storage" {
  description = "[PROPOSTA] a calibrar: armazenamento inicial em GiB (gp3)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Limite do storage autoscaling em GiB; 0 desliga o autoscaling de storage"
  type        = number
  default     = 0
}

variable "backup_retention_period" {
  description = "Dias de retencao dos backups automaticos (PITR). Decisao do projeto: 7 (04-terraform.md). O Free plan limita este valor (FreeTierRestrictionError com 7); conta Free usa um valor menor via tfvars, documentado em ADR. 0 desliga o PITR."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period deve estar entre 0 e 35 (limite do RDS)."
  }
}

variable "subnet_ids" {
  description = "Subnets PRIVADAS (em pelo menos 2 AZs) do subnet group"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "O subnet group do RDS exige subnets em pelo menos 2 AZs."
  }
}

variable "vpc_security_group_ids" {
  description = "Security Groups associados a instancia (ingress 5432 so a partir do SG das tasks)"
  type        = list(string)
}

variable "deletion_protection" {
  description = "Protecao contra exclusao; explicito (sem default) para a decisao ficar registrada no tfvars"
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Se true, o destroy nao cria snapshot final; explicito (sem default) para a decisao ficar registrada no tfvars"
  type        = bool
}

variable "final_snapshot_identifier" {
  description = "Identificador do snapshot final; obrigatorio quando skip_final_snapshot = false"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags aplicadas ao subnet group e a instancia"
  type        = map(string)
  default     = {}
}

variable "iam_database_authentication_enabled" {
  description = "Habilita a autenticacao IAM do RDS (token no lugar de senha) para usuarios com a role rds_iam. Exige memoria livre na instancia (a doc da AWS cita 300 a 1000 MiB; atencao em classes burstable)"
  type        = bool
  default     = false
}
