provider "aws" {
  region = var.region

  # Tags obrigatorias (02-finops-guardrails.md). Track = eks; TTL = horario de expiracao do lab (ISO 8601 em UTC):
  # o eks-lab.yml agendado destroi o lab depois dele.
  default_tags {
    tags = {
      Project   = var.project_name
      Env       = var.environment
      Track     = "eks"
      Owner     = var.owner
      ManagedBy = "terraform"
      TTL       = var.ttl
    }
  }
}
