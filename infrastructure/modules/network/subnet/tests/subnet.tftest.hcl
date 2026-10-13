mock_provider "aws" {}

variables {
  vpc_id            = "vpc-mock"
  subnet_name       = ["pub-a", "pub-b"]
  subnet_cidr       = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zone = ["test-az-a", "test-az-b"]
}

# Listas com tamanhos diferentes devem falhar na validation (sem wrap-around silencioso do element()).
run "listas_desiguais_falham" {
  command = plan

  variables {
    subnet_cidr = ["10.0.1.0/24"]
  }

  expect_failures = [var.subnet_name]
}

run "az_a_menos_falha" {
  command = plan

  variables {
    availability_zone = ["test-az-a"]
  }

  expect_failures = [var.subnet_name]
}

# map_public_ip_on_launch chega ao recurso (true).
run "map_public_ip_true" {
  command = plan

  variables {
    map_public_ip_on_launch = true
  }

  assert {
    condition     = alltrue([for k, s in aws_subnet.this : s.map_public_ip_on_launch == true])
    error_message = "map_public_ip_on_launch=true nao chegou ao aws_subnet."
  }

  assert {
    condition     = length(aws_subnet.this) == 2
    error_message = "Esperava 2 subnets."
  }
}

# Default (false) tambem chega ao recurso.
run "map_public_ip_default_false" {
  command = plan

  assert {
    condition     = alltrue([for k, s in aws_subnet.this : s.map_public_ip_on_launch == false])
    error_message = "map_public_ip_on_launch deveria ser false por padrao."
  }
}
