variable "region" {
  description = "Regiao AWS (us-east-1, travada)"
  type        = string
  default     = "us-east-1"
}

variable "ttl" {
  description = "Tag TTL (efemero): hora limite para a varredura de residuos"
  type        = string
  default     = "ephemeral-rds-smoke"
}

variable "vpc_cidr_block" {
  description = "CIDR da VPC efemera (pequena: so o RDS vive aqui)"
  type        = string
  default     = "10.200.0.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDRs das 2 subnets privadas (2 AZs; o subnet group do RDS exige 2 AZs)"
  type        = list(string)
  default     = ["10.200.0.0/26", "10.200.0.64/26"]
}

variable "db_engine_version" {
  description = "Versao do PostgreSQL (major 16; default confirmado 16.13 em us-east-1)"
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Classe da instancia (db.t4g.micro, elegivel ao Free Tier)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Storage gp3 em GiB (minimo 20 para db.t4g.micro gp3)"
  type        = number
  default     = 20
}

variable "backup_retention_period" {
  description = "Dias de PITR a testar no Free plan. 7 falhou (FreeTierRestrictionError); este root descobre o maximo aceito."
  type        = number
  default     = 1
}
