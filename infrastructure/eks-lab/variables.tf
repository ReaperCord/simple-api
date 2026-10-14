variable "project_name" {
  description = "Nome do projeto (tag Project e prefixo dos recursos)"
  type        = string
  default     = "simple-api"
}

variable "environment" {
  description = "Ambiente (tag Env); o lab usa a stack principal desse ambiente"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Regiao AWS (a mesma da stack principal)"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Valor da tag Owner"
  type        = string
  default     = "leandro"
}

variable "ttl" {
  description = "Horario de expiracao do lab (ISO 8601 em UTC, ex.: 2026-10-14T22:00:00Z), vida maxima de 6 h; sem default: quem sobe o lab decide"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", var.ttl))
    error_message = "ttl deve ser um horario ISO 8601 em UTC no formato 2026-10-14T22:00:00Z."
  }
}

variable "state_bucket" {
  description = "Bucket S3 do state da stack principal (leitura via terraform_remote_state)"
  type        = string
}

variable "state_key" {
  description = "Key do state da stack principal (leitura via terraform_remote_state)"
  type        = string
}

variable "kubernetes_version" {
  description = "Versao do Kubernetes em SUPORTE PADRAO (US$ 0,10/h). Suporte estendido custa US$ 0,60/h e e proibido: o cluster fixa upgrade_policy = STANDARD. Conferir `aws eks describe-cluster-versions` antes de mudar"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "Tipo dos nos. Free plan: t4g.small on-demand (elegivel ao Free Tier); Paid plan: t4g.medium Spot"
  type        = string
  default     = "t4g.small"
}

variable "node_capacity_type" {
  description = "ON_DEMAND (Free plan) ou SPOT (Paid plan)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type deve ser ON_DEMAND ou SPOT."
  }
}

variable "node_min_size" {
  description = "Minimo de nos"
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Nos desejados"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximo de nos"
  type        = number
  default     = 3
}

variable "addon_versions" {
  description = "Versoes dos add-ons gerenciados, fixadas (conferidas com `aws eks describe-addon-versions` para a versao do cluster em 14/10/2026)"
  type        = map(string)
  default = {
    "vpc-cni"                = "v1.23.2-eksbuild.3"
    "coredns"                = "v1.14.7-eksbuild.11"
    "kube-proxy"             = "v1.36.0-eksbuild.45"
    "eks-pod-identity-agent" = "v1.4.0-eksbuild.4"
    "metrics-server"         = "v0.9.0-eksbuild.12"
  }
}

variable "admin_principal_arns" {
  description = "ARNs IAM extras com acesso de administrador ao cluster (ex.: o usuario que opera o lab). Quem cria o cluster (a role do workflow) ja e admin. Valores com account id entram pelo workflow ou por -var, nunca no Git"
  type        = list(string)
  default     = []
}

variable "app_namespace" {
  description = "Namespace Kubernetes da aplicacao"
  type        = string
  default     = "simple-api"
}

variable "app_service_account" {
  description = "ServiceAccount da aplicacao (associada a role do Pod Identity)"
  type        = string
  default     = "simple-api"
}

variable "db_app_username" {
  description = "Usuario do banco usado pela app (so CONNECT, autenticacao IAM; ver docs/usuario-db-iam.md)"
  type        = string
  default     = "app_connect"
}

variable "enable_api_route" {
  description = "Etapa 2: cria as rotas ANY /eks e ANY /eks/{proxy+} no API Gateway da stack principal, apontando para o NLB interno criado pelo AWS Load Balancer Controller. So true depois de o NLB existir"
  type        = bool
  default     = false
}

variable "nlb_service_stack" {
  description = "Valor da tag service.k8s.aws/stack do NLB criado pelo controller (namespace/nome do Service)"
  type        = string
  default     = "simple-api/simple-api"
}

variable "nlb_listener_port" {
  description = "Porta do listener do NLB (a porta do Service)"
  type        = number
  default     = 80
}
