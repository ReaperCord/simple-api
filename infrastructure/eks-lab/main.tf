# Root do laboratorio EKS (efemero, TTL de 6 h). Le a stack principal (VPC, subnets, RDS, API Gateway) por
# terraform_remote_state e NUNCA a altera: tudo o que o lab precisa nela entra como recurso PROPRIO deste root
# (regra de SG, tags de subnet, rotas) e some no destroy do lab. Custo ~US$ 0,17/h (plano de controle) mais nos e NLB.
# Sem NAT, sem Fargate, sem Karpenter, sem suporte estendido (07-eks-lab.md, 01-arquitetura-e-restricoes.md).

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "main" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = var.state_key
    region = var.region
  }
}

locals {
  name = "${var.project_name}-${var.environment}-eks"

  main               = data.terraform_remote_state.main.outputs
  vpc_id             = local.main.vpc_id
  public_subnet_ids  = local.main.public_subnet_ids
  private_subnet_ids = local.main.private_subnet_ids

  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
}

data "aws_vpc" "main" {
  id = local.vpc_id
}

# ---------------------------------------------------------------------------------------------
# Roles do plano de controle e dos nos (politicas gerenciadas pela AWS; nomes com o prefixo do projeto).
# ---------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "eks_assume" {
  statement {
    sid     = "EksControlPlane"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    sid     = "Ec2Nodes"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
  tags               = { Component = "iam" }
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  name               = "${local.name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = { Component = "iam" }
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",          # os nos entram no cluster
    "AmazonEKS_CNI_Policy",               # o VPC CNI gerencia as ENIs dos pods
    "AmazonEC2ContainerRegistryReadOnly", # pull das imagens do ECR
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

# ---------------------------------------------------------------------------------------------
# Cluster. Nos e plano de controle nas subnets PUBLICAS da stack principal (sem NAT; o auto-assign de IPv4 publico
# das subnets e obrigatorio para o no entrar no cluster). Autenticacao so por API (access entries, sem aws-auth).
# ---------------------------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = local.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  # Os add-ons de rede sao gerenciados abaixo, com versao fixada (nao os autoinstalados).
  bootstrap_self_managed_addons = false

  # Suporte PADRAO (US$ 0,10/h). Estendido (US$ 0,60/h) e proibido pela steering.
  upgrade_policy {
    support_type = "STANDARD"
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = local.public_subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]

  tags = merge({ Name = local.name }, { Component = "eks-control-plane" })
}

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
  tags          = { Component = "iam" }
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# ---------------------------------------------------------------------------------------------
# Add-ons: VPC CNI e kube-proxy antes dos nos; CoreDNS, Pod Identity Agent e metrics-server (o HPA depende dele)
# depois. Versoes fixadas em var.addon_versions.
# ---------------------------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = var.addon_versions["vpc-cni"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = { Component = "eks-addons" }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = var.addon_versions["kube-proxy"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = { Component = "eks-addons" }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = local.public_subnet_ids # sem Fargate e sem NAT: nos em subnet publica com IPv4 publico

  ami_type       = "AL2023_ARM_64_STANDARD" # t4g e Graviton (ARM64), como as tasks do ECS
  capacity_type  = var.node_capacity_type
  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
  ]

  tags = merge({ Name = "${local.name}-ng" }, { Component = "eks-nodes" })
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = var.addon_versions["coredns"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
  tags       = { Component = "eks-addons" }
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = var.addon_versions["eks-pod-identity-agent"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
  tags       = { Component = "eks-addons" }
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  addon_version               = var.addon_versions["metrics-server"]
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
  tags       = { Component = "eks-addons" }
}

# ---------------------------------------------------------------------------------------------
# Pod Identity: roles assumidas pelos pods (sem segredo, sem OIDC provider). Dois consumidores:
#  - o AWS Load Balancer Controller, com a policy do repo (config/policies/alb_controller_policy.json): so aqui, nunca
#    em role de ECS (03-devsecops.md);
#  - a app, com rds-db:connect no usuario app_connect e nessa instancia (ADR 0013), sem acesso a segredo.
# ---------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "pods_assume" {
  statement {
    sid     = "EksPodIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

module "lbc_role" {
  source = "../modules/security/iam-role"

  role_name               = "${local.name}-lbc"
  assume_role_policy_json = data.aws_iam_policy_document.pods_assume.json
  policy_json             = file("${path.module}/../config/policies/alb_controller_policy.json")
  tags                    = { Component = "iam" }
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = module.lbc_role.role_arn

  depends_on = [aws_eks_addon.pod_identity_agent]
  tags       = { Component = "iam" }
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ConnectAsAppUser"
    effect    = "Allow"
    actions   = ["rds-db:connect"] # gera o token de autenticacao IAM do RDS
    resources = ["arn:${local.partition}:rds-db:${var.region}:${local.account_id}:dbuser:${local.main.rds_resource_id}/${var.db_app_username}"]
  }
}

module "app_role" {
  source = "../modules/security/iam-role"

  role_name               = "${local.name}-app"
  assume_role_policy_json = data.aws_iam_policy_document.pods_assume.json
  policy_json             = data.aws_iam_policy_document.app.json
  tags                    = { Component = "iam" }
}

resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.app_namespace
  service_account = var.app_service_account
  role_arn        = module.app_role.role_arn

  depends_on = [aws_eks_addon.pod_identity_agent]
  tags       = { Component = "iam" }
}

# ---------------------------------------------------------------------------------------------
# Rede: regras PROPRIAS do lab em SGs da stack principal e do cluster (somem no destroy do lab).
# ---------------------------------------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = local.main.rds_security_group_id
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "EKS lab (temporario): pods e nos ate o RDS"
  tags                         = { Component = "database" }
}

# O NLB (alvos por IP) e os health checks chegam aos pods na porta da app, vindos da propria VPC.
resource "aws_vpc_security_group_ingress_rule" "pods_from_vpc" {
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  cidr_ipv4         = data.aws_vpc.main.cidr_block
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
  description       = "EKS lab (temporario): NLB interno e VPC Link ate os pods na porta da app"
  tags              = { Component = "network" }
}

# O AWS Load Balancer Controller escolhe as subnets do NLB INTERNO pela tag abaixo; so as privadas a recebem.
resource "aws_ec2_tag" "internal_elb" {
  for_each = toset(local.private_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}
