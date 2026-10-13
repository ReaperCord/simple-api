output "state_bucket_name" {
  description = "Bucket S3 do state da stack principal (-backend-config=bucket=...; vars.TF_STATE_BUCKET nos workflows)"
  value       = aws_s3_bucket.state.bucket
}

output "state_key" {
  description = "Chave do state da stack principal (-backend-config=key=...; vars.TF_STATE_KEY nos workflows)"
  value       = local.state_key
}

output "region" {
  description = "Regiao do backend (-backend-config=region=...)"
  value       = var.region
}

output "ecr_repository_name" {
  description = "Nome do repositorio ECR (var ecr_repository_name da stack principal)"
  value       = module.ecr.repository_name
}

output "ecr_repository_url" {
  description = "URL do repositorio ECR (sem tag)"
  value       = module.ecr.repository_url
}

output "gha_plan_role_arn" {
  description = "ARN da role gha-plan (vars.AWS_PLAN_ROLE_ARN no GitHub)"
  value       = module.oidc.role_arns["gha-plan"]
}

output "gha_deploy_role_arn" {
  description = "ARN da role gha-deploy (vars.AWS_DEPLOY_ROLE_ARN no GitHub)"
  value       = module.oidc.role_arns["gha-deploy"]
}

output "gha_infra_role_arn" {
  description = "ARN da role gha-infra (vars.AWS_INFRA_ROLE_ARN no GitHub)"
  value       = module.oidc.role_arns["gha-infra"]
}

output "budget_name" {
  description = "Nome do budget mensal"
  value       = module.budget.budget_name
}
