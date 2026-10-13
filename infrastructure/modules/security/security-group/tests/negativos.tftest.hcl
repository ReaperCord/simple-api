mock_provider "aws" {}

variables {
  name        = "test-sg"
  description = "SG de teste"
  vpc_id      = "vpc-mock"
  sg_ids      = { ecs = "sg-ecs-mock" }
}

# n1: sg_ref fora de sg_ids -> precondition (a chave so e conhecida no plan).
run "n1_sg_ref_fora_de_sg_ids" {
  command = plan

  variables {
    ingress_rules = [{
      rule_key    = "from-typo"
      description = "ref inexistente"
      protocol    = "tcp"
      from_port   = 3000
      to_port     = 3000
      sg_refs     = ["typo"]
    }]
  }

  expect_failures = [aws_vpc_security_group_ingress_rule.this]
}

# n2: rule_key duplicado na mesma direcao.
run "n2_rule_key_duplicado" {
  command = plan

  variables {
    ingress_rules = [
      {
        rule_key    = "dup"
        description = "a"
        protocol    = "tcp"
        from_port   = 3000
        to_port     = 3000
        sg_refs     = ["ecs"]
      },
      {
        rule_key    = "dup"
        description = "b"
        protocol    = "tcp"
        from_port   = 3001
        to_port     = 3001
        sg_refs     = ["ecs"]
      }
    ]
  }

  expect_failures = [var.ingress_rules]
}

# n3: dois tipos de origem na mesma regra.
run "n3_dois_tipos_de_origem" {
  command = plan

  variables {
    ingress_rules = [{
      rule_key    = "misto"
      description = "cidr + sg"
      protocol    = "tcp"
      from_port   = 3000
      to_port     = 3000
      cidr_blocks = ["10.0.0.0/16"]
      sg_refs     = ["ecs"]
    }]
  }

  expect_failures = [var.ingress_rules]
}

# n4: ingress aberto para o mundo (IPv4).
run "n4_ingress_0_0_0_0" {
  command = plan

  variables {
    ingress_rules = [{
      rule_key    = "aberto"
      description = "mundo"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_blocks = ["0.0.0.0/0"]
    }]
  }

  expect_failures = [var.ingress_rules]
}

# n4b: ingress aberto para o mundo (IPv6).
run "n4b_ingress_ipv6_aberto" {
  command = plan

  variables {
    ingress_rules = [{
      rule_key         = "aberto6"
      description      = "mundo v6"
      protocol         = "tcp"
      from_port        = 443
      to_port          = 443
      ipv6_cidr_blocks = ["::/0"]
    }]
  }

  expect_failures = [var.ingress_rules]
}

# n5: protocol != -1 sem portas (ingress).
run "n5_porta_ausente_ingress" {
  command = plan

  variables {
    ingress_rules = [{
      rule_key    = "sem-porta"
      description = "sem porta"
      protocol    = "tcp"
      sg_refs     = ["ecs"]
    }]
  }

  expect_failures = [var.ingress_rules]
}

# n5b: protocol != -1 sem portas (egress).
run "n5b_porta_ausente_egress" {
  command = plan

  variables {
    egress_rules = [{
      rule_key    = "sem-porta"
      description = "sem porta"
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
    }]
  }

  expect_failures = [var.egress_rules]
}

# Egress aceita 0.0.0.0/0 (a restricao e so do ingress) e protocol -1 dispensa portas.
run "egress_aberto_e_protocolo_todos_sao_validos" {
  command = plan

  variables {
    egress_rules = [{
      rule_key    = "all-out"
      description = "tudo para fora"
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }]
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 1
    error_message = "Esperava 1 regra de egress."
  }
}

# Chaves do for_each sao estaticas e independentes da ordem das regras.
run "chaves_estaticas_do_for_each" {
  command = plan

  variables {
    egress_rules = [
      {
        rule_key    = "https-443"
        description = "https"
        protocol    = "tcp"
        from_port   = 443
        to_port     = 443
        cidr_blocks = ["0.0.0.0/0"]
      },
      {
        rule_key    = "to-ecs"
        description = "ecs"
        protocol    = "tcp"
        from_port   = 3000
        to_port     = 3000
        sg_refs     = ["ecs"]
      }
    ]
  }

  assert {
    condition = (
      sort(keys(aws_vpc_security_group_egress_rule.this)) ==
      sort(["https-443/cidr4/0.0.0.0/0", "to-ecs/sg/ecs"])
    )
    error_message = "As chaves do for_each devem ser <rule_key>/<tipo>/<alvo>."
  }
}
