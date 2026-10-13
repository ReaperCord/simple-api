terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # Backend PARCIAL: bucket, key e region entram por -backend-config (valores em vars.* do GitHub,
  # nunca no repo). use_lockfile grava <key>.tflock no proprio bucket (Terraform >= 1.11).
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
