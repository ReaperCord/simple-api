resource "aws_db_subnet_group" "this" {
  name        = "${var.identifier}-subnets"
  description = "Subnets privadas do RDS ${var.identifier}"
  subnet_ids  = var.subnet_ids
  tags        = var.tags
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.master_username
  port     = var.port

  # Senha gerada e guardada pelo RDS no Secrets Manager (rotacao padrao de 7 dias).
  # Nenhuma senha passa pelo Terraform nem pelo state (03-devsecops.md).
  manage_master_user_password = true

  # Autenticacao IAM (opcional): a app entra como um usuario so com CONNECT, sem senha guardada.
  # A senha master continua gerenciada pelo RDS; o usuario master NAO ganha a role rds_iam.
  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.vpc_security_group_ids
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = var.backup_retention_period
  copy_tags_to_snapshot   = true

  # Decisao documentada (plano-implementacao.md, decisao 13): explicitos, sem depender do default.
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.skip_final_snapshot || var.final_snapshot_identifier != null
      error_message = "skip_final_snapshot = false exige final_snapshot_identifier."
    }
  }
}
