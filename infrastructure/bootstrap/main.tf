# Root de bootstrap: aplicado UMA vez, com state LOCAL (nunca versionado, nunca aberto: e sensivel).
# Cria o que a stack principal precisa existir antes: bucket de state, repositorio ECR, budget
# e o acesso do GitHub Actions (OIDC + roles gha-plan, gha-deploy, gha-infra, gha-infra-plan e gha-eks-lab).
# Nenhum apply roda sem aprovacao explicita do Leandro (AGENTS.md, regras 7 e 12).

data "aws_caller_identity" "current" {}

locals {
  # Convencao de nomes compartilhada com o root principal (infrastructure/main.tf).
  name = "${var.project_name}-${var.environment}"

  state_bucket_name   = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
  state_key           = "${var.project_name}/${var.environment}/terraform.tfstate"
  ecr_repository_name = var.ecr_repository_name != "" ? var.ecr_repository_name : var.project_name
}

# ---------------------------------------------------------------------------------------------
# Bucket do state remoto da stack principal (use_lockfile = true grava <key>.tflock no mesmo bucket).
# ---------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket_name
  force_destroy = false
  tags          = { Component = "terraform-state" }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Planos salvos pelo infra.yml (plans/<run>/tfplan): so servem entre o job plan e o job apply do mesmo run.
# Expiram em 7 dias (e as versoes antigas em 1), para nao acumular planos com dados do ambiente. O state nao e afetado.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expira-planos-salvos"
    status = "Enabled"

    filter {
      prefix = "plans/"
    }

    expiration {
      days = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# ---------------------------------------------------------------------------------------------
# ECR (a primeira imagem e publicada entre o bootstrap e a stack; ver 06-cicd.md).
# ---------------------------------------------------------------------------------------------
module "ecr" {
  source = "../modules/ecr"

  repository_name = local.ecr_repository_name
  max_image_count = var.ecr_max_image_count
  tags            = { Component = "registry" }
}

# ---------------------------------------------------------------------------------------------
# AWS Budgets: ANTES do primeiro apply da stack (02-finops-guardrails.md).
# ---------------------------------------------------------------------------------------------
module "budget" {
  source = "../modules/budget"

  name                       = "${var.project_name}-monthly"
  limit_amount               = var.budget_limit_amount
  subscriber_email_addresses = var.budget_emails
  tags                       = { Component = "finops" }
}

# ---------------------------------------------------------------------------------------------
# OIDC do GitHub + roles do pipeline (gha-plan, gha-deploy, gha-infra, gha-infra-plan e gha-eks-lab).
# Os nomes de cluster, service e roles da task seguem a convencao de local.name do root principal.
# ---------------------------------------------------------------------------------------------
module "oidc" {
  source = "../modules/oidc"

  github_owner       = var.github_owner
  github_repo        = var.github_repo
  github_owner_id    = var.github_owner_id
  github_repo_id     = var.github_repo_id
  project_name       = var.project_name
  region             = var.region
  state_bucket_name  = aws_s3_bucket.state.bucket
  state_key          = local.state_key
  ecr_repository_arn = module.ecr.repository_arn
  ecs_cluster_name   = local.name
  ecs_service_name   = local.name
  task_role_names    = ["${local.name}-ecs-exec", "${local.name}-ecs-task"]
  tags               = { Component = "ci-cd" }
}

# ---------------------------------------------------------------------------------------------
# Resource Group para observar tudo do projeto no console da AWS (Resource Groups & Tag Editor).
# Gratuito. Consulta por tag: agrupa bootstrap e stack (Project = project_name) e acompanha os
# recursos que a stack criar ou destruir, sem depender de apply do pipeline.
# ---------------------------------------------------------------------------------------------
resource "aws_resourcegroups_group" "project" {
  name = "kxc-${var.project_name}-RG"
  # A API aceita so [\sa-zA-Z0-9_.-] na descricao (sem acento, virgula, igual ou parenteses).
  description = "Todos os recursos do projeto ${var.project_name} - tag Project - bootstrap e stack"

  resource_query {
    type = "TAG_FILTERS_1_0"
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters = [
        {
          Key    = "Project"
          Values = [var.project_name]
        }
      ]
    })
  }
  tags = { Component = "finops" }
}
