resource "aws_ecr_repository" "this" {
  name = var.repository_name
  # IMMUTABLE: a tag (SHA do commit) nunca e sobrescrita; o deploy referencia a imagem por digest.
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete
  tags                 = var.tags

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Mantem so as ultimas N imagens (tagueadas ou nao) para limitar o custo de armazenamento.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter as ultimas ${var.max_image_count} imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
