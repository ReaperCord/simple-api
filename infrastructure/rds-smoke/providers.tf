provider "aws" {
  region = var.region

  # Tags obrigatorias (02-finops-guardrails.md). Track=shared como no RDS da stack principal;
  # TTL marcado para a varredura de residuos saber que e efemero.
  default_tags {
    tags = {
      Project   = "simple-api"
      Env       = "dev"
      Track     = "shared"
      Owner     = "leandro"
      ManagedBy = "terraform"
      TTL       = var.ttl
    }
  }
}
