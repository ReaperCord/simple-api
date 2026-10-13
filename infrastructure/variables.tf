#==========================================================================
# PROJETO
#==========================================================================
variable "project_name" {
  description = "Nome do projeto (tag Project e prefixo dos recursos; as roles gha-infra so enxergam recursos com este prefixo)"
  type        = string
}

variable "environment" {
  description = "Ambiente (tag Env e sufixo dos nomes)"
  type        = string

  validation {
    condition     = contains(["dev", "hml", "prod"], var.environment)
    error_message = "environment deve ser dev, hml ou prod."
  }
}

variable "region" {
  description = "Regiao AWS da stack (definida no tfvars)"
  type        = string
}

variable "owner" {
  description = "Valor da tag Owner"
  type        = string
  default     = "leandro"
}

variable "ttl" {
  description = "Valor da tag TTL (data ISO ou none)"
  type        = string
  default     = "none"
}

#==========================================================================
# REDE
#==========================================================================
variable "vpc_cidr_block" {
  description = "CIDR da VPC"
  type        = string
}

variable "az_count" {
  description = "Quantidade de AZs usadas (as primeiras de data.aws_availability_zones); precisa ser igual ao tamanho das listas de subnets"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count deve ser pelo menos 2 (o subnet group do RDS exige 2 AZs)."
  }
}

variable "public_subnet_names" {
  description = "Nomes das subnets publicas (uma por AZ)"
  type        = list(string)
}

variable "private_subnet_names" {
  description = "Nomes das subnets privadas (uma por AZ)"
  type        = list(string)
}

variable "subnet_cidr_blocks_public" {
  description = "CIDRs das subnets publicas, na ordem de public_subnet_names"
  type        = list(string)
}

variable "subnet_cidr_blocks_private" {
  description = "CIDRs das subnets privadas, na ordem de private_subnet_names"
  type        = list(string)
}

variable "tags_vpc" {
  description = "Tags da VPC (a tag Track=shared e acrescentada no main.tf)"
  type        = map(string)
  default     = {}
}

variable "tags_public_subnet" {
  description = "Tags das subnets publicas"
  type        = map(string)
  default     = {}
}

variable "tags_private_subnet" {
  description = "Tags das subnets privadas"
  type        = map(string)
  default     = {}
}

variable "tags_internet_gateway" {
  description = "Tags do Internet Gateway"
  type        = map(string)
  default     = {}
}

variable "tags_rt_public" {
  description = "Tags das route tables publicas"
  type        = map(string)
  default     = {}
}

variable "tags_rt_private" {
  description = "Tags das route tables privadas (sem rotas alem da local)"
  type        = map(string)
  default     = {}
}

#==========================================================================
# ECR / IMAGEM
#==========================================================================
variable "ecr_repository_name" {
  description = "Nome do repositorio ECR criado pelo bootstrap (lido por data source, o state do bootstrap e local)"
  type        = string
}

variable "image_tag" {
  description = "Tag da imagem (SHA do commit) ja publicada no ECR; nunca latest"
  type        = string

  validation {
    condition     = var.image_tag != "latest" && var.image_tag != ""
    error_message = "image_tag deve ser a tag SHA de uma imagem publicada (ECR e IMMUTABLE), nunca latest."
  }
}

#==========================================================================
# ECS
#==========================================================================
variable "container_name" {
  description = "Nome do container na task definition"
  type        = string
  default     = "simple-api"
}

variable "container_port" {
  description = "Porta da aplicacao (API_PORT)"
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "CPU da task Fargate (512 = 0,5 vCPU)"
  type        = number
}

variable "task_memory" {
  description = "Memoria da task Fargate em MiB (1024 e o minimo com 512 de CPU)"
  type        = number
}

variable "desired_count" {
  description = "Quantidade inicial de tasks (depois do primeiro apply o autoscaling controla; ignorado pelo ignore_changes)"
  type        = number
}

variable "autoscaling_min_capacity" {
  description = "Minimo de tasks do autoscaling"
  type        = number
}

variable "autoscaling_max_capacity" {
  description = "Maximo de tasks do autoscaling"
  type        = number
}

variable "log_retention_in_days" {
  description = "[PROPOSTA] a calibrar: retencao dos logs da aplicacao no CloudWatch"
  type        = number
  default     = 14
}

variable "log_level" {
  description = "LOG_LEVEL da aplicacao (debug, info, warn ou error)"
  type        = string
  default     = "info"
}

variable "db_pool_max" {
  description = "DB_POOL_MAX da aplicacao (limite de conexoes por task; ver conta de conexoes em 01-arquitetura-e-restricoes.md)"
  type        = number
  default     = 3
}

#==========================================================================
# RDS
#==========================================================================
variable "db_engine_version" {
  description = "Versao major do PostgreSQL (mesma do docker-compose); conferir com aws rds describe-db-engine-versions antes do apply"
  type        = string
}

variable "db_instance_class" {
  description = "Classe da instancia RDS"
  type        = string
}

variable "db_name" {
  description = "Nome do banco (DB_DATABASE)"
  type        = string
}

variable "db_username" {
  description = "Usuario master do banco (DB_USER); a senha e gerenciada pelo RDS no Secrets Manager"
  type        = string
}

variable "db_allocated_storage" {
  description = "[PROPOSTA] a calibrar: armazenamento do RDS em GiB (gp3)"
  type        = number
}

variable "db_deletion_protection" {
  description = "Protecao contra exclusao do RDS (explicita; false porque a stack e destruida apos cada janela de avaliacao)"
  type        = bool
}

variable "db_skip_final_snapshot" {
  description = "Pular o snapshot final no destroy (explicito; true evita custo residual de snapshot)"
  type        = bool
}

variable "db_final_snapshot_identifier" {
  description = "Identificador do snapshot final; obrigatorio quando db_skip_final_snapshot = false"
  type        = string
  default     = null
}

#==========================================================================
# API GATEWAY
#==========================================================================
variable "api_throttling_rate_limit" {
  description = "[PROPOSTA] a calibrar: requisicoes por segundo do estagio $default (subir temporariamente para o teste de spike)"
  type        = number
}

variable "api_throttling_burst_limit" {
  description = "[PROPOSTA] a calibrar: burst do estagio $default"
  type        = number
}

#==========================================================================
# ALARMES MINIMOS (sem acao SNS por padrao)
#==========================================================================
variable "alarm_action_arns" {
  description = "ARNs de acao dos alarmes (ex: topico SNS); vazio = alarmes sem notificacao"
  type        = list(string)
  default     = []
}

variable "alarm_rds_cpu_credit_balance_min" {
  description = "[PROPOSTA] a calibrar: alarma quando CPUCreditBalance do RDS fica abaixo deste valor"
  type        = number
}

variable "alarm_rds_free_storage_min_bytes" {
  description = "[PROPOSTA] a calibrar: alarma quando FreeStorageSpace do RDS fica abaixo deste valor (bytes)"
  type        = number
}

variable "alarm_api_5xx_max" {
  description = "[PROPOSTA] a calibrar: alarma quando a soma de respostas 5xx da API em um periodo passa deste valor"
  type        = number
}
