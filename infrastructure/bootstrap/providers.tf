provider "aws" {
  region = var.region

  # Tags obrigatorias (02-finops-guardrails.md). Track=bootstrap: estes recursos sobrevivem ao
  # destroy da stack e sao ignorados pela varredura de residuos.
  default_tags {
    tags = {
      Project   = var.project_name
      Env       = var.environment
      Track     = "bootstrap"
      Owner     = var.owner
      ManagedBy = "terraform"
      TTL       = var.ttl
    }
  }
}
