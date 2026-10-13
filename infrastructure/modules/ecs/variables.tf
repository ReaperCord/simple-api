variable "cluster_name" {
  description = "Nome do cluster ECS"
  type        = string
}

variable "service_name" {
  description = "Nome do serviço ECS (também usado como family da task definition)"
  type        = string
}

variable "region" {
  description = "Região AWS usada para configuração de logs"
  type        = string
}

variable "container_name" {
  description = "Nome do container dentro da task definition"
  type        = string
}

variable "container_image" {
  description = "URI da imagem do container (ex: ECR)"
  type        = string
}

variable "container_port" {
  description = "Porta em que a aplicação escuta dentro do container"
  type        = number
  default     = 3000
}

variable "cpu_architecture" {
  description = "Arquitetura de CPU da task Fargate (ARM64 ou X86_64); a imagem precisa ser multi-arch ou da mesma arquitetura"
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture deve ser ARM64 ou X86_64."
  }
}

variable "task_cpu" {
  description = "CPU alocada para a task (unidades Fargate; 512 = 0,5 vCPU)"
  type        = number
  default     = 512

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.task_cpu)
    error_message = "task_cpu deve ser 256, 512, 1024, 2048, 4096, 8192 ou 16384."
  }
}

variable "task_memory" {
  description = "Memória alocada para a task (MiB); precisa ser uma combinação válida com task_cpu no Fargate"
  type        = number
  default     = 1024

  # Combinações do Fargate (Linux): https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html
  validation {
    condition = (
      var.task_cpu == 256 ? contains([512, 1024, 2048], var.task_memory) :
      var.task_cpu == 512 ? contains([1024, 2048, 3072, 4096], var.task_memory) :
      var.task_cpu == 1024 ? (var.task_memory >= 2048 && var.task_memory <= 8192 && var.task_memory % 1024 == 0) :
      var.task_cpu == 2048 ? (var.task_memory >= 4096 && var.task_memory <= 16384 && var.task_memory % 1024 == 0) :
      var.task_cpu == 4096 ? (var.task_memory >= 8192 && var.task_memory <= 30720 && var.task_memory % 1024 == 0) :
      var.task_cpu == 8192 ? (var.task_memory >= 16384 && var.task_memory <= 61440 && var.task_memory % 4096 == 0) :
      var.task_cpu == 16384 ? (var.task_memory >= 32768 && var.task_memory <= 122880 && var.task_memory % 8192 == 0) :
      false
    )
    error_message = "Combinacao task_cpu/task_memory invalida no Fargate (ex: 512 de CPU aceita 1024 a 4096 MiB; 512 MiB so existe com 256 de CPU)."
  }
}

variable "desired_count" {
  description = "Quantidade desejada de tasks em execução"
  type        = number
  default     = 1
}

variable "execution_role_arn" {
  description = "ARN da IAM Role de execução da task (pull de imagem, logs, secrets)"
  type        = string
}

variable "task_role_arn" {
  description = "ARN da IAM Role da aplicação (permissões em runtime)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Lista de subnets onde as tasks serão executadas"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Lista de Security Groups associados às tasks"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Se as tasks devem receber IP público (necessário em subnets públicas sem NAT)"
  type        = bool
  default     = false
}

variable "target_group_arn" {
  description = "ARN do Target Group para registrar as tasks (null quando não há LB)"
  type        = string
  default     = null
}

variable "environment_variables" {
  description = "Variáveis de ambiente injetadas no container"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  description = "Secrets injetados no container a partir do SSM/Secrets Manager"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "stop_timeout" {
  description = "Segundos que o ECS espera o container encerrar apos SIGTERM antes do SIGKILL (stopTimeout)"
  type        = number
  default     = 30
}

variable "health_check_interval" {
  description = "Intervalo (s) do healthCheck do container"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Timeout (s) de cada execucao do healthCheck do container"
  type        = number
  default     = 5
}

variable "health_check_retries" {
  description = "Falhas consecutivas ate o container ser considerado unhealthy"
  type        = number
  default     = 3
}

variable "health_check_start_period" {
  description = "Periodo de carencia (s) apos o start em que falhas do healthCheck nao contam"
  type        = number
  default     = 15
}

variable "deployment_minimum_healthy_percent" {
  description = "Percentual minimo de tasks saudaveis durante um deploy"
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Percentual maximo de tasks (em relacao ao desired_count) durante um deploy"
  type        = number
  default     = 200
}

variable "service_registry_arn" {
  description = "ARN do servico Cloud Map (registro SRV) para o service_registries; null desliga o registro"
  type        = string
  default     = null
}

variable "container_insights" {
  description = "Habilita o Container Insights no cluster"
  type        = bool
  default     = false
}

variable "log_retention_in_days" {
  description = "Retenção dos logs no CloudWatch"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags aplicadas aos recursos ECS"
  type        = map(string)
  default     = {}
}
