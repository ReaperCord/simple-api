# Stack principal (trilha ECS): API Gateway HTTP API -> VPC Link V2 -> Cloud Map (SRV) ->
# ECS Fargate ARM64 -> RDS PostgreSQL privado. Sem ALB e sem NAT (01-arquitetura-e-restricoes.md).
#
# FinOps: a stack roda 24x7 SO durante a janela de avaliacao e e destruida em seguida
# (terraform destroy + tools/residual-check.sh). Nada daqui e aplicado sem aprovacao explicita.
#
# Ordem de composicao (04-terraform.md): vpc -> subnets -> igw -> route tables/rotas publicas ->
# route tables privadas (sem rotas) -> security groups -> rds -> cloud map -> iam -> ecs ->
# apigw -> autoscaling -> alarmes -> outputs.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Exclui Local Zones e Wavelength Zones (so zonas que nao exigem opt-in).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# O state do bootstrap e local, entao o repositorio ECR e lido por nome (sem remote state).
data "aws_ecr_repository" "this" {
  name = var.ecr_repository_name
}

locals {
  # Convencao de nomes compartilhada com o bootstrap (infrastructure/bootstrap/main.tf): o
  # OIDC do bootstrap monta os ARNs do service e das roles da task a partir dela.
  name = "${var.project_name}-${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Chaves ESTATICAS (nomes das subnets) para o for_each das rotas: o ID do IGW so entra no valor.
  public_route_table_index = { for i, n in var.public_subnet_names : n => i }

  # VPC, SGs e RDS pertencem a camada compartilhada (usada tambem pelo lab EKS).
  shared_tags = { Track = "shared" }

  # Regras de SG: JSON lido com jsondecode(file()), nunca templatefile (04-terraform.md, regra 9).
  rules_vpclink = jsondecode(file("${path.module}/config/security_rules/rules-sg-vpclink.json"))
  rules_ecs     = jsondecode(file("${path.module}/config/security_rules/rules-sg-ecs.json"))
  rules_rds     = jsondecode(file("${path.module}/config/security_rules/rules-sg-rds.json"))

  # O MESMO mapa vai para os tres modulos de SG: as chaves sao estaticas e os IDs so aparecem
  # como valor, entao nao ha ciclo nem Invalid for_each.
  sg_ids = {
    vpclink = module.sg_vpclink.security_group_id
    ecs     = module.sg_ecs.security_group_id
    rds     = module.sg_rds.security_group_id
  }

  execution_role_name = "${local.name}-ecs-exec"
  task_role_name      = "${local.name}-ecs-task"

  # ARN do log group construido (o log group nasce dentro do modulo ecs; referenciar a saida
  # criaria ciclo modulo ecs <-> role de execucao).
  log_group_arn = "arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/${local.name}:*"
}

#==========================================================================
# REDE
#==========================================================================
module "vpc" {
  source = "./modules/network/vpc"

  vpc_cidr_block = var.vpc_cidr_block
  tags           = merge(var.tags_vpc, local.shared_tags)
}

module "public_subnets" {
  source = "./modules/network/subnet"

  vpc_id                  = module.vpc.vpc_id
  subnet_name             = var.public_subnet_names
  subnet_cidr             = var.subnet_cidr_blocks_public
  availability_zone       = local.azs
  map_public_ip_on_launch = true
  tags                    = var.tags_public_subnet
}

module "private_subnets" {
  source = "./modules/network/subnet"

  vpc_id                  = module.vpc.vpc_id
  subnet_name             = var.private_subnet_names
  subnet_cidr             = var.subnet_cidr_blocks_private
  availability_zone       = local.azs
  map_public_ip_on_launch = false
  tags                    = var.tags_private_subnet
}

module "igw" {
  source = "./modules/network/internet-gateway"

  vpc_id = module.vpc.vpc_id
  tags   = var.tags_internet_gateway
}

module "public_route_tables" {
  source = "./modules/network/route-table"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.public_subnets.subnet_ids_ordered
  tags       = var.tags_rt_public
}

# Uma instancia do modulo route por route table publica (rota default via IGW).
module "public_routes" {
  source   = "./modules/network/route"
  for_each = local.public_route_table_index

  route_table_id = module.public_route_tables.route_table_ids[each.value]
  routes_json    = file("${path.module}/config/routes/public.json")
  ref_ids        = { igw = module.igw.internet_gateway_id }
}

module "public_route_table_associations" {
  source = "./modules/network/route-table-association"

  subnet_ids      = module.public_subnets.subnet_ids_ordered
  route_table_ids = module.public_route_tables.route_table_ids
}

# Route tables privadas SEM rotas: so a rota local da VPC. NAT nunca (config/routes/private.json nao e usado).
module "private_route_tables" {
  source = "./modules/network/route-table"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.private_subnets.subnet_ids_ordered
  tags       = var.tags_rt_private
}

module "private_route_table_associations" {
  source = "./modules/network/route-table-association"

  subnet_ids      = module.private_subnets.subnet_ids_ordered
  route_table_ids = module.private_route_tables.route_table_ids
}

#==========================================================================
# SECURITY GROUPS (mesmo mapa sg_ids nas tres instancias)
#==========================================================================
module "sg_vpclink" {
  source = "./modules/security/security-group"

  name          = "${local.name}-vpclink"
  description   = "VPC Link do API Gateway: saida para as tasks ECS"
  vpc_id        = module.vpc.vpc_id
  tags          = merge({ Name = "${local.name}-vpclink" }, local.shared_tags)
  sg_ids        = local.sg_ids
  ingress_rules = local.rules_vpclink.ingress
  egress_rules  = local.rules_vpclink.egress
}

module "sg_ecs" {
  source = "./modules/security/security-group"

  name          = "${local.name}-ecs"
  description   = "Tasks ECS: entrada so do VPC Link, saida para RDS e AWS"
  vpc_id        = module.vpc.vpc_id
  tags          = merge({ Name = "${local.name}-ecs" }, local.shared_tags)
  sg_ids        = local.sg_ids
  ingress_rules = local.rules_ecs.ingress
  egress_rules  = local.rules_ecs.egress
}

module "sg_rds" {
  source = "./modules/security/security-group"

  name          = "${local.name}-rds"
  description   = "RDS PostgreSQL: entrada so das tasks ECS"
  vpc_id        = module.vpc.vpc_id
  tags          = merge({ Name = "${local.name}-rds" }, local.shared_tags)
  sg_ids        = local.sg_ids
  ingress_rules = local.rules_rds.ingress
  egress_rules  = local.rules_rds.egress
}

#==========================================================================
# RDS (subnets privadas, sem IP publico)
#==========================================================================
module "rds" {
  source = "./modules/rds"

  identifier                = "${local.name}-db"
  engine_version            = var.db_engine_version
  instance_class            = var.db_instance_class
  db_name                   = var.db_name
  master_username           = var.db_username
  allocated_storage         = var.db_allocated_storage
  backup_retention_period   = var.db_backup_retention_period
  subnet_ids                = module.private_subnets.subnet_ids_ordered
  vpc_security_group_ids    = [module.sg_rds.security_group_id]
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_final_snapshot_identifier
  tags                      = merge({ Name = "${local.name}-db" }, local.shared_tags)
}

#==========================================================================
# CLOUD MAP (registro SRV)
#==========================================================================
module "cloudmap" {
  source = "./modules/cloudmap"

  namespace_name = "${var.environment}.${var.project_name}.local"
  vpc_id         = module.vpc.vpc_id
  service_name   = "api"
  # O deregister das tasks pelo ECS e assincrono: sem isso o destroy pode falhar com o servico ainda "em uso".
  force_destroy = true
}

#==========================================================================
# IAM DA TASK (execucao e aplicacao)
#==========================================================================
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    sid     = "EcsTasksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    # Confused deputy: so tasks desta conta assumem as roles.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "execution" {
  # Resource "*": a AWS nao aceita ARN em ecr:GetAuthorizationToken.
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"] # login no registry para o pull da imagem
    resources = ["*"]
  }

  statement {
    sid    = "EcrPullImage"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",               # baixa o manifesto da imagem
      "ecr:GetDownloadUrlForLayer",      # baixa as camadas da imagem
      "ecr:BatchCheckLayerAvailability", # verifica as camadas no pull
    ]
    resources = [data.aws_ecr_repository.this.arn]
  }

  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream", # um stream por task no log group do servico
      "logs:PutLogEvents",    # envia os logs do container
    ]
    resources = [local.log_group_arn]
  }
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "ReadDatabaseSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"] # a app le a senha do RDS (rotacionada a cada 7 dias) ao abrir conexao
    resources = [module.rds.master_user_secret_arn]
  }
}

module "execution_role" {
  source = "./modules/security/iam-role"

  role_name               = local.execution_role_name
  assume_role_policy_json = data.aws_iam_policy_document.ecs_tasks_assume.json
  policy_json             = data.aws_iam_policy_document.execution.json
}

module "task_role" {
  source = "./modules/security/iam-role"

  role_name               = local.task_role_name
  assume_role_policy_json = data.aws_iam_policy_document.ecs_tasks_assume.json
  policy_json             = data.aws_iam_policy_document.task.json
}

#==========================================================================
# ECS (tasks em subnets publicas com IP publico; SG aceita so o VPC Link)
#==========================================================================
module "ecs" {
  source = "./modules/ecs"

  cluster_name          = local.name
  service_name          = local.name
  region                = var.region
  container_name        = var.container_name
  container_port        = var.container_port
  container_image       = "${data.aws_ecr_repository.this.repository_url}:${var.image_tag}"
  task_cpu              = var.task_cpu
  task_memory           = var.task_memory
  desired_count         = var.desired_count
  execution_role_arn    = module.execution_role.role_arn
  task_role_arn         = module.task_role.role_arn
  subnet_ids            = module.public_subnets.subnet_ids_ordered
  security_group_ids    = [module.sg_ecs.security_group_id]
  assign_public_ip      = true
  service_registry_arn  = module.cloudmap.service_arn
  log_retention_in_days = var.log_retention_in_days

  # Nenhuma senha aqui: a app le o segredo do RDS no Secrets Manager (DB_SECRET_ARN).
  environment_variables = [
    { name = "API_PORT", value = tostring(var.container_port) },
    { name = "DB_HOST", value = module.rds.address },
    { name = "DB_PORT", value = tostring(module.rds.port) },
    { name = "DB_DATABASE", value = module.rds.db_name },
    { name = "DB_USER", value = var.db_username },
    { name = "DB_SSLMODE", value = "verify-full" },
    { name = "DB_POOL_MAX", value = tostring(var.db_pool_max) },
    { name = "DB_SECRET_ARN", value = module.rds.master_user_secret_arn },
    { name = "LOG_LEVEL", value = var.log_level },
  ]
}

#==========================================================================
# API GATEWAY (VPC Link V2 nas subnets privadas)
#==========================================================================
module "apigw" {
  source = "./modules/apigw"

  name                        = local.name
  vpc_link_subnet_ids         = module.private_subnets.subnet_ids_ordered
  vpc_link_security_group_ids = [module.sg_vpclink.security_group_id]
  integration_uri             = module.cloudmap.service_arn
  throttling_rate_limit       = var.api_throttling_rate_limit
  throttling_burst_limit      = var.api_throttling_burst_limit
}

#==========================================================================
# AUTOSCALING
#==========================================================================
module "autoscaling" {
  source = "./modules/autoscaling"

  cluster_name = module.ecs.cluster_name
  service_name = module.ecs.service_name
  min_capacity = var.autoscaling_min_capacity
  max_capacity = var.autoscaling_max_capacity
}

#==========================================================================
# ALARMES MINIMOS (limiares por variavel, [PROPOSTA] a calibrar)
#==========================================================================
resource "aws_cloudwatch_metric_alarm" "rds_cpu_credit_balance" {
  alarm_name          = "${local.name}-rds-cpu-credit-balance-low"
  alarm_description   = "Credito de CPU do RDS (t4g) baixo: acima do baseline o T4g Unlimited cobra credito extra."
  namespace           = "AWS/RDS"
  metric_name         = "CPUCreditBalance"
  dimensions          = { DBInstanceIdentifier = module.rds.instance_id }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.alarm_rds_cpu_credit_balance_min
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${local.name}-rds-free-storage-low"
  alarm_description   = "Pouco espaco livre no storage do RDS."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = module.rds.instance_id }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alarm_rds_free_storage_min_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns
}

# Metrica de HTTP API: nome "5xx" e dimensoes ApiId + Stage
# (https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-metrics.html).
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.name}-api-5xx"
  alarm_description   = "Respostas 5xx do API Gateway acima do limiar."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = module.apigw.api_id, Stage = module.apigw.stage_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alarm_api_5xx_max
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns
}
