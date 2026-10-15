output "provider_arn" {
  description = "ARN do provider OIDC do GitHub"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "role_arns" {
  description = "ARN de cada role do pipeline, por nome (gha-plan, gha-deploy, gha-infra, gha-infra-plan, gha-eks-lab)"
  value       = { for k, m in module.role : k => m.role_arn }
}

output "role_names" {
  description = "Nomes das roles do pipeline (gha-plan, gha-deploy, gha-infra, gha-infra-plan, gha-eks-lab)"
  value       = keys(local.role_subjects)
}

output "role_subjects" {
  description = "Claim sub exata aceita pela trust policy de cada role"
  value       = local.role_subjects
}

output "trust_policies" {
  description = "JSON da trust policy de cada role (aud e sub exatos)"
  value       = local.trust_policies
}
