mock_provider "aws" {}

variables {
  identifier             = "test-db"
  engine_version         = "16"
  db_name                = "appdb"
  master_username        = "master"
  subnet_ids             = ["subnet-aaa", "subnet-bbb"]
  vpc_security_group_ids = ["sg-123"]
  deletion_protection    = false
  skip_final_snapshot    = true
}

# Padrao: senha master gerenciada pelo RDS (nada de senha no state) e autenticacao IAM desligada.
run "padrao_sem_iam_e_com_senha_gerenciada" {
  command = plan

  assert {
    condition     = aws_db_instance.this.iam_database_authentication_enabled == false
    error_message = "A autenticacao IAM deve vir desligada por padrao."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true
    error_message = "A senha master deve ser gerenciada pelo RDS."
  }

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false && aws_db_instance.this.storage_encrypted == true
    error_message = "O RDS deve ser privado e cifrado."
  }
}

run "iam_ligado_quando_pedido" {
  command = plan

  variables {
    iam_database_authentication_enabled = true
  }

  assert {
    condition     = aws_db_instance.this.iam_database_authentication_enabled == true
    error_message = "A flag de autenticacao IAM deve chegar na instancia."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == true
    error_message = "Com IAM ligado a senha master continua gerenciada pelo RDS."
  }
}
