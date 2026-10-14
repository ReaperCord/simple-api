#==========================================================================
# PROJECT CONFIGURATION
#==========================================================================
project_name = "simple-api"
environment  = "dev"
region       = "us-east-1"
ttl          = "none"

#==========================================================================
# NETWORK CONFIGURATION
#==========================================================================
# VPC Configuration
vpc_cidr_block = "10.100.0.0/16"

# Subnets (as AZs vem de data.aws_availability_zones; az_count = tamanho das listas abaixo)
az_count                   = 2
public_subnet_names        = ["public-subnet-1a", "public-subnet-1b"]
private_subnet_names       = ["private-subnet-1a", "private-subnet-1b"]
subnet_cidr_blocks_public  = ["10.100.1.0/24", "10.100.2.0/24"]
subnet_cidr_blocks_private = ["10.100.11.0/24", "10.100.12.0/24"]

# Network Tags
tags_vpc = {
  Name = "simple-api-vpc-dev"
  Type = "vpc"
}

tags_public_subnet = {
  Name = "simple-api-public-subnet-dev"
  Type = "public"
}

tags_private_subnet = {
  Name = "simple-api-private-subnet-dev"
  Type = "private"
}

tags_internet_gateway = {
  Name = "simple-api-igw-dev"
  Type = "internet-gateway"
}

tags_rt_public = {
  Name = "simple-api-public-rt-dev"
  Type = "public"
}

tags_rt_private = {
  Name = "simple-api-private-rt-dev"
  Type = "private"
}

#==========================================================================
# ECR / IMAGEM
#==========================================================================
# Repositorio criado pelo bootstrap. A tag da imagem (SHA do commit) NAO fica aqui:
# entra por -var image_tag=<sha> (input image_tag do infra.yml).
ecr_repository_name = "simple-api"

#==========================================================================
# ECS (0,5 vCPU / 1 GB, ARM64 e o default do modulo)
#==========================================================================
task_cpu                 = 512
task_memory              = 1024
desired_count            = 1
autoscaling_min_capacity = 1
autoscaling_max_capacity = 3
log_retention_in_days    = 14 # [PROPOSTA] a calibrar
log_level                = "info"
db_pool_max              = 3

#==========================================================================
# RDS
#==========================================================================
# engine_version: major 16 (mesma do docker-compose). Conferido em 2026-10-12 com
#   aws rds describe-db-engine-versions --engine postgres --profile kxc-readonly --region us-east-1
# (default da major 16 = 16.13; db.t4g.micro gp3 orderable, minimo de 20 GiB). Reconferir antes do apply.
db_engine_version    = "16"
db_instance_class    = "db.t4g.micro"
db_name              = "simple_api"
db_username          = "simple_api"
db_allocated_storage = 20 # [PROPOSTA] a calibrar (GiB, gp3)

# PITR: a decisao travada era 7 dias (04-terraform.md), mas o Free plan desta conta recusa 7
# (FreeTierRestrictionError: "backup retention period exceeds the maximum available to free tier").
# Testado em 2026-10-13 pelo root efemero infrastructure/rds-smoke: 7 falha, 1 cria o RDS.
# Reduzido para 1 na conta Free (PITR de 1 dia); documentado em ADR.
db_backup_retention_period = 1

# Decisao documentada: a stack e destruida apos cada janela de avaliacao; um snapshot final
# geraria custo residual. Para manter o dado, use deletion_protection = true e
# skip_final_snapshot = false com db_final_snapshot_identifier.
db_deletion_protection = false
db_skip_final_snapshot = true

#==========================================================================
# API GATEWAY - throttling do estagio $default
#==========================================================================
api_throttling_rate_limit  = 50  # [PROPOSTA] a calibrar com o baseline de carga (req/s)
api_throttling_burst_limit = 100 # [PROPOSTA] a calibrar com o baseline de carga

#==========================================================================
# ALARMES MINIMOS (sem acao SNS; defina alarm_action_arns para notificar)
#==========================================================================
alarm_rds_cpu_credit_balance_min = 20         # [PROPOSTA] a calibrar
alarm_rds_free_storage_min_bytes = 2147483648 # [PROPOSTA] a calibrar (2 GiB)
alarm_api_5xx_max                = 5          # [PROPOSTA] a calibrar (respostas 5xx em 5 minutos)

#==========================================================================
# AUTENTICACAO DO BANCO
#==========================================================================
# true: a app entra como db_app_username (so CONNECT) com token IAM, sem senha guardada e sem acesso ao
# segredo master. Depois do apply, rode tools/run-db-init.sh UMA vez (cria o usuario); ate la /connect responde 503.
# A escolha vale desde o primeiro apply (o service ignora mudancas de task definition). Ver docs/usuario-db-iam.md.
db_iam_auth     = true
db_app_username = "app_connect"
