mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.100.0.0/16"
    }
  }

  # O JSON do policy document e calculado pelo provider; no mock precisa ser um JSON valido.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# A stack principal nao existe no teste: o state remoto e simulado.
override_data {
  target = data.terraform_remote_state.main
  values = {
    outputs = {
      vpc_id                    = "vpc-111"
      public_subnet_ids         = ["subnet-pub-a", "subnet-pub-b"]
      private_subnet_ids        = ["subnet-prv-a", "subnet-prv-b"]
      rds_security_group_id     = "sg-rds"
      vpclink_security_group_id = "sg-vpclink"
      rds_resource_id           = "db-ABCDEFGHIJKL01234"
      rds_address               = "db.exemplo.rds.amazonaws.com"
      rds_port                  = 5432
      rds_db_name               = "appdb"
      api_id                    = "api123"
      vpc_link_id               = "vl123"
    }
  }
}

variables {
  state_bucket = "test-tfstate"
  state_key    = "simple-api/dev/terraform.tfstate"
  ttl          = "2026-10-14T22:00:00Z"
}

# Cluster em suporte PADRAO (o estendido custa US$ 0,60/h e e proibido), so por API e nas subnets PUBLICAS (sem NAT).
run "cluster_padrao_sem_suporte_estendido_e_em_subnets_publicas" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "O cluster deve fixar upgrade_policy = STANDARD (suporte estendido e proibido)."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API"
    error_message = "A autenticacao do cluster deve ser so por API (access entries)."
  }

  assert {
    condition     = toset(aws_eks_cluster.this.vpc_config[0].subnet_ids) == toset(["subnet-pub-a", "subnet-pub-b"])
    error_message = "O cluster deve usar as subnets PUBLICAS (nao ha NAT)."
  }

  assert {
    condition     = aws_eks_cluster.this.bootstrap_self_managed_addons == false
    error_message = "Os add-ons de rede devem ser os gerenciados, com versao fixada."
  }
}

# Nos Graviton on-demand (Free plan) em subnets publicas, sem Fargate.
run "nos_t4g_small_on_demand_em_subnets_publicas" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this.ami_type == "AL2023_ARM_64_STANDARD"
    error_message = "Os nos devem ser ARM64 (AL2023)."
  }

  assert {
    condition     = aws_eks_node_group.this.capacity_type == "ON_DEMAND" && toset(aws_eks_node_group.this.instance_types) == toset(["t4g.small"])
    error_message = "Free plan: t4g.small on-demand."
  }

  assert {
    condition     = toset(aws_eks_node_group.this.subnet_ids) == toset(["subnet-pub-a", "subnet-pub-b"])
    error_message = "Os nos devem ficar nas subnets publicas."
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].min_size == 2 && aws_eks_node_group.this.scaling_config[0].max_size == 3
    error_message = "Escala dos nos: 2 a 3."
  }
}

run "addons_fixados_incluindo_metrics_server_e_pod_identity" {
  command = plan

  assert {
    condition = alltrue([
      aws_eks_addon.vpc_cni.addon_name == "vpc-cni",
      aws_eks_addon.kube_proxy.addon_name == "kube-proxy",
      aws_eks_addon.coredns.addon_name == "coredns",
      aws_eks_addon.pod_identity_agent.addon_name == "eks-pod-identity-agent",
      aws_eks_addon.metrics_server.addon_name == "metrics-server",
    ])
    error_message = "Devem existir os 5 add-ons: VPC CNI, kube-proxy, CoreDNS, Pod Identity Agent e metrics-server (o HPA depende dele)."
  }

  assert {
    condition     = aws_eks_addon.metrics_server.addon_version == "v0.9.0-eksbuild.12"
    error_message = "A versao do metrics-server deve vir fixada de var.addon_versions."
  }
}

run "pod_identity_do_controller_e_da_app" {
  command = plan

  assert {
    condition     = aws_eks_pod_identity_association.lbc.namespace == "kube-system" && aws_eks_pod_identity_association.lbc.service_account == "aws-load-balancer-controller"
    error_message = "O Pod Identity do controller deve valer so para a SA do controller em kube-system."
  }

  assert {
    condition     = aws_eks_pod_identity_association.app.namespace == "simple-api" && aws_eks_pod_identity_association.app.service_account == "simple-api"
    error_message = "O Pod Identity da app deve valer so para a SA simple-api no namespace simple-api."
  }
}

# Regras PROPRIAS do lab: o RDS recebe a porta 5432 so do SG do cluster; os pods, a 3000 so de dentro da VPC.
run "regras_de_rede_proprias_do_lab" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.rds_from_eks.security_group_id == "sg-rds" && aws_vpc_security_group_ingress_rule.rds_from_eks.from_port == 5432 && aws_vpc_security_group_ingress_rule.rds_from_eks.to_port == 5432
    error_message = "O RDS deve receber 5432 do SG do cluster."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.pods_from_vpc.from_port == 3000 && aws_vpc_security_group_ingress_rule.pods_from_vpc.cidr_ipv4 == "10.100.0.0/16"
    error_message = "Os pods devem receber 3000 so da VPC."
  }

  assert {
    condition     = length(aws_ec2_tag.internal_elb) == 2 && alltrue([for t in aws_ec2_tag.internal_elb : t.key == "kubernetes.io/role/internal-elb" && t.value == "1"])
    error_message = "Somente as 2 subnets privadas recebem a tag do NLB interno."
  }
}

# Etapa 1 nao toca no API Gateway; a etapa 2 cria as duas rotas ANY /eks e ANY /eks/{proxy+}.
run "api_gateway_so_na_etapa_2" {
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_route.eks_proxy) == 0 && length(aws_apigatewayv2_route.eks_root) == 0 && length(aws_vpc_security_group_egress_rule.vpclink_to_nlb) == 0
    error_message = "Sem enable_api_route nao pode haver rota nem regra de saida do VPC Link."
  }
}

run "etapa_2_cria_as_duas_rotas_eks" {
  command = plan

  variables {
    enable_api_route = true
  }

  assert {
    condition     = aws_apigatewayv2_route.eks_proxy[0].route_key == "ANY /eks/{proxy+}" && aws_apigatewayv2_route.eks_root[0].route_key == "ANY /eks"
    error_message = "As rotas do lab devem ser ANY /eks/{proxy+} e ANY /eks."
  }

  assert {
    condition     = aws_apigatewayv2_integration.eks_proxy[0].request_parameters["overwrite:path"] == "/$request.path.proxy" && aws_apigatewayv2_integration.eks_root[0].request_parameters["overwrite:path"] == "/"
    error_message = "O prefixo /eks deve sair do caminho enviado ao pod (overwrite:path)."
  }
}

run "ttl_invalido_falha" {
  command = plan

  variables {
    ttl = "amanha"
  }

  expect_failures = [var.ttl]
}

run "node_capacity_type_invalido_falha" {
  command = plan

  variables {
    node_capacity_type = "RESERVED"
  }

  expect_failures = [var.node_capacity_type]
}
