terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # Root EFEMERO de verificacao (teste barato de RDS, Forma 2): state LOCAL, nunca versionado,
  # nunca toca o state da stack principal. So existe para provar que o Free plan desta conta
  # deixa CRIAR um RDS db.t4g.micro. Aplicar, confirmar, destruir, rodar residual-check.
}
