mock_provider "aws" {}

variables {
  repository_name = "test-repo"
}

run "imutavel_com_scan_e_aes256" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "O repositorio ECR deve ser IMMUTABLE."
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push == true
    error_message = "scan_on_push deve ser true."
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "A criptografia deve ser AES256."
  }

  assert {
    condition     = aws_ecr_repository.this.force_delete == false
    error_message = "force_delete deve ser false por padrao."
  }
}

run "lifecycle_usa_max_image_count" {
  command = plan

  variables {
    max_image_count = 7
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 7
    error_message = "A lifecycle policy deve manter max_image_count imagens."
  }
}

run "max_image_count_zero_falha" {
  command = plan

  variables {
    max_image_count = 0
  }

  expect_failures = [var.max_image_count]
}
