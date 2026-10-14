terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  # Backend PARCIAL, como a stack principal: bucket, key e region entram por -backend-config. A key do lab e propria
  # (<key da stack>/eks-lab/terraform.tfstate): o state do lab nunca se mistura com o da stack principal.
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}
