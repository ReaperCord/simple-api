provider "aws" {
  region = var.region

  # Tags obrigatorias (02-finops-guardrails.md). VPC, SGs e RDS sobrescrevem Track=shared pelo
  # parametro tags do recurso/modulo (a tag do recurso vence a de default_tags).
  default_tags {
    tags = {
      Project   = var.project_name
      Env       = var.environment
      Track     = "ecs"
      Owner     = var.owner
      ManagedBy = "terraform"
      TTL       = var.ttl
    }
  }
}
