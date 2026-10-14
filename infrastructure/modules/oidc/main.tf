data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id

  # Claim sub de cada role (03-devsecops.md). Sem curingas no contexto: cada workflow roda num
  # environment proprio do GitHub, entao um nao consegue assumir a role do outro.
  # gha-eks-lab: roda so o root infrastructure/eks-lab no environment eks-lab (sem aprovacao; o destroy agendado por TTL
  # precisa rodar sozinho). Ver o fim deste arquivo.
  #
  # Dois formatos de sub por role (lista fechada, sem curinga):
  #  - por NOME: repo:OWNER/REPO:<contexto>            (repos criados ate 15/07/2026)
  #  - IMUTAVEL: repo:OWNER@OWNER-ID/REPO@REPO-ID:<ctx> (repos criados apos 15/07/2026; este fork)
  # Fonte: https://docs.github.com/actions/reference/security/oidc#immutable-subject-claims
  # O separador @ nao aparece em nome de usuario nem de repo, entao StringLike aqui nao abre curinga real.
  github_sub_prefix_name      = "repo:${var.github_owner}/${var.github_repo}"
  github_sub_prefix_immutable = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
  role_contexts = {
    "gha-plan"    = "pull_request"
    "gha-deploy"  = "environment:deploy"
    "gha-infra"   = "environment:infra"
    "gha-eks-lab" = "environment:eks-lab"
  }
  role_subjects = {
    for role, ctx in local.role_contexts : role => [
      "${local.github_sub_prefix_name}:${ctx}",
      "${local.github_sub_prefix_immutable}:${ctx}",
    ]
  }

  trust_policies = {
    for role, subs in local.role_subjects : role => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect    = "Allow"
          Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
          Action    = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            }
            # StringLike porque sao dois valores fechados (nome e imutavel); nenhum traz curinga.
            StringLike = {
              "token.actions.githubusercontent.com:sub" = subs
            }
          }
        }
      ]
    })
  }

  role_policies = {
    "gha-plan"    = data.aws_iam_policy_document.plan.json
    "gha-deploy"  = data.aws_iam_policy_document.deploy.json
    "gha-infra"   = data.aws_iam_policy_document.infra.json
    "gha-eks-lab" = data.aws_iam_policy_document.eks_lab.json
  }

  # ARNs construidos (sem account ID ou regiao literal).
  state_bucket_arn = "arn:${local.partition}:s3:::${var.state_bucket_name}"
  state_object_arn = "${local.state_bucket_arn}/${var.state_key}"
  state_lock_arn   = "${local.state_bucket_arn}/${var.state_key}.tflock"

  ecs_service_arn    = "arn:${local.partition}:ecs:${var.region}:${local.account_id}:service/${var.ecs_cluster_name}/${var.ecs_service_name}"
  task_role_arns     = [for n in var.task_role_names : "arn:${local.partition}:iam::${local.account_id}:role/${n}"]
  project_role_arn   = "arn:${local.partition}:iam::${local.account_id}:role/${var.project_name}-*"
  project_policy_arn = "arn:${local.partition}:iam::${local.account_id}:policy/${var.project_name}-*"
  # Prefixo de ARN regional; o servico entra no %s via format() (ex: format("${local.regional_prefix}:*", "ec2")).
  regional_prefix = "arn:${local.partition}:%s:${var.region}:${local.account_id}"
  apigateway_arn  = "arn:${local.partition}:apigateway:${var.region}::"
}

# Um provider OIDC do GitHub por conta. thumbprint_list nao e informado: no provider 6.68.0 o
# atributo e opcional/computado (schema conferido com 'terraform providers schema -json').
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

module "role" {
  source   = "../security/iam-role"
  for_each = local.role_subjects

  role_name               = each.key
  assume_role_policy_json = local.trust_policies[each.key]
  policy_json             = local.role_policies[each.key]
  tags                    = var.tags
}

resource "aws_iam_policy" "infra_iam_state" {
  name        = "gha-infra-iam-state-policy"
  description = "gha-infra: IAM do projeto, leitura do ECR e state"
  policy      = data.aws_iam_policy_document.infra_iam_state.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "infra_iam_state" {
  role       = module.role["gha-infra"].role_name
  policy_arn = aws_iam_policy.infra_iam_state.arn
}

# ---------------------------------------------------------------------------------------------
# gha-plan: leitura + state. Roda em pull_request; nao escreve em nenhum recurso da stack.
# ---------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "plan" {
  # Leituras de refresh do terraform plan. Resource "*" porque Describe*/List* nao aceitam ARN
  # (excecao da tabela de 03-devsecops.md: leituras do gha-plan).
  statement {
    sid       = "ReadStackResources"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:Describe*",                               # VPC, subnets, route tables, IGW, SGs e AZs (data.aws_availability_zones)
      "rds:Describe*",                               # instancia e subnet group do RDS
      "rds:ListTagsForResource",                     # tags do RDS no refresh
      "ecs:Describe*",                               # cluster, service e task definition
      "ecs:List*",                                   # listagens usadas no refresh do ECS
      "ecr:DescribeRepositories",                    # data.aws_ecr_repository
      "ecr:DescribeImages",                          # data.aws_ecr_repository: o provider aws 6.x tambem chama DescribeImages (mesmo gap da gha-infra; plan do ci.yml falhava com AccessDenied)
      "ecr:ListTagsForResource",                     # tags do repositorio no data source
      "servicediscovery:Get*",                       # namespace e servico do Cloud Map
      "servicediscovery:List*",                      # tags e listagens do Cloud Map
      "logs:DescribeLogGroups",                      # log group do ECS
      "logs:ListTagsForResource",                    # tags do log group
      "cloudwatch:DescribeAlarms",                   # alarmes da stack
      "cloudwatch:ListTagsForResource",              # tags dos alarmes
      "application-autoscaling:Describe*",           # scalable target e policy
      "application-autoscaling:ListTagsForResource", # tags do scalable target
      "iam:GetRole",                                 # roles de execucao e da task
      "iam:ListRolePolicies",                        # policies inline da role
      "iam:ListAttachedRolePolicies",                # policies anexadas a role
      "iam:ListInstanceProfilesForRole",             # exigido pelo refresh de aws_iam_role
      "iam:ListRoleTags",                            # tags da role
      "iam:GetPolicy",                               # policy gerenciada da role
      "iam:GetPolicyVersion",                        # documento da policy
      "iam:ListPolicyVersions",                      # versoes da policy
      "iam:ListPolicyTags",                          # tags da policy
    ]
  }

  # API Gateway v2 aceita ARN: leitura so de APIs, VPC links e tags da regiao.
  statement {
    sid     = "ReadApiGateway"
    effect  = "Allow"
    actions = ["apigateway:GET"] # leitura da HTTP API, rotas, integracao, estagio e VPC link no refresh
    resources = [
      "${local.apigateway_arn}/apis",
      "${local.apigateway_arn}/apis/*",
      "${local.apigateway_arn}/vpclinks",
      "${local.apigateway_arn}/vpclinks/*",
      "${local.apigateway_arn}/tags/*",
    ]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"] # backend S3 lista o bucket para localizar o state
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"] # le o state remoto da stack (somente leitura)
    resources = [local.state_object_arn]
  }

  # A trava nativa do S3 (use_lockfile) grava o objeto <key>.tflock tambem no plan.
  statement {
    sid    = "StateLockObject"
    effect = "Allow"
    actions = [
      "s3:GetObject",    # le o lock existente
      "s3:PutObject",    # cria o lock (PutObject condicional)
      "s3:DeleteObject", # libera o lock ao fim do plan
    ]
    resources = [local.state_lock_arn]
  }
}

# ---------------------------------------------------------------------------------------------
# gha-deploy: build/push da imagem e UpdateService. Roda no environment "deploy".
# ---------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "deploy" {
  # Resource "*": a AWS nao aceita ARN em ecr:GetAuthorizationToken (excecao da tabela de 03-devsecops.md).
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"] # docker login no registry
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability", # push: verifica camadas ja enviadas
      "ecr:InitiateLayerUpload",         # push: inicia o upload de camada
      "ecr:UploadLayerPart",             # push: envia partes da camada
      "ecr:CompleteLayerUpload",         # push: conclui o upload da camada
      "ecr:PutImage",                    # push: grava o manifesto da imagem
      "ecr:BatchGetImage",               # Trivy image e pull do manifesto
      "ecr:GetDownloadUrlForLayer",      # Trivy image e pull de camadas
      "ecr:DescribeImages",              # checa se a tag do commit ja existe antes do push
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid    = "EcsUpdateService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",    # aponta o service para a nova revisao da task definition
      "ecs:DescribeServices", # espera a estabilidade e captura a revisao anterior para rollback
    ]
    resources = [local.ecs_service_arn]
  }

  # Resource "*": o ECS nao suporta permissao por recurso em task definitions (excecao da tabela de 03-devsecops.md).
  statement {
    sid    = "EcsTaskDefinition"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition", # registra a nova revisao com a imagem por digest
      "ecs:DescribeTaskDefinition", # le a revisao ativa para renderizar a nova
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassTaskRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"] # a task definition referencia as roles de execucao e da aplicacao
    resources = local.task_role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------------------------
# gha-infra: aplica a stack principal. Roda no environment "infra" (aprovacao manual).
# Risco residual: pode criar roles/policies com o prefixo do projeto (ver README).
# ---------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "infra" {
  # Resource "*": Describe* nao aceita ARN.
  statement {
    sid       = "DescribeRegional"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:Describe*",                                     # refresh de rede e AZs
      "rds:Describe*",                                     # refresh do RDS
      "ecs:Describe*",                                     # refresh do ECS
      "ecs:List*",                                         # listagens do ECS
      "servicediscovery:Get*",                             # refresh do Cloud Map e espera das operacoes assincronas
      "servicediscovery:List*",                            # listagens do Cloud Map
      "cloudwatch:DescribeAlarms",                         # nao aceita ARN
      "application-autoscaling:RegisterScalableTarget",    # scalable target do service (nao aceita ARN)
      "application-autoscaling:DeregisterScalableTarget",  # destroy do scalable target (nao aceita ARN)
      "application-autoscaling:PutScalingPolicy",          # policy de target tracking (nao aceita ARN)
      "application-autoscaling:DeleteScalingPolicy",       # destroy da policy (nao aceita ARN)
      "application-autoscaling:DescribeScalableTargets",   # refresh (nao aceita ARN)
      "application-autoscaling:DescribeScalingPolicies",   # refresh (nao aceita ARN)
      "application-autoscaling:DescribeScalingActivities", # espera do scaling (nao aceita ARN)
      "application-autoscaling:ListTagsForResource",       # tags do scalable target
      "application-autoscaling:TagResource",               # tags do scalable target
      "application-autoscaling:UntagResource",             # tags do scalable target
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # Resource "*": o ECS nao suporta permissao por recurso em task definitions.
  statement {
    sid       = "EcsRegisterTaskDefinition"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"] # revisao inicial da task definition
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "Ec2Network"
    effect    = "Allow"
    resources = [format("${local.regional_prefix}:*", "ec2")]
    actions = [
      "ec2:CreateVpc",                                  # VPC
      "ec2:DeleteVpc",                                  # destroy da VPC
      "ec2:ModifyVpcAttribute",                         # enable_dns_support e enable_dns_hostnames
      "ec2:CreateSubnet",                               # subnets publicas e privadas
      "ec2:DeleteSubnet",                               # destroy das subnets
      "ec2:ModifySubnetAttribute",                      # map_public_ip_on_launch
      "ec2:CreateInternetGateway",                      # IGW
      "ec2:DeleteInternetGateway",                      # destroy do IGW
      "ec2:AttachInternetGateway",                      # IGW na VPC
      "ec2:DetachInternetGateway",                      # destroy do IGW
      "ec2:CreateRouteTable",                           # route tables
      "ec2:DeleteRouteTable",                           # destroy das route tables
      "ec2:CreateRoute",                                # rota default das subnets publicas
      "ec2:ReplaceRoute",                               # update da rota
      "ec2:DeleteRoute",                                # destroy da rota
      "ec2:AssociateRouteTable",                        # route table x subnet
      "ec2:DisassociateRouteTable",                     # destroy da associacao
      "ec2:CreateSecurityGroup",                        # SGs do VPC Link, ECS e RDS
      "ec2:DeleteSecurityGroup",                        # destroy dos SGs
      "ec2:AuthorizeSecurityGroupIngress",              # regras aws_vpc_security_group_ingress_rule
      "ec2:AuthorizeSecurityGroupEgress",               # regras aws_vpc_security_group_egress_rule
      "ec2:RevokeSecurityGroupIngress",                 # remocao de regras
      "ec2:RevokeSecurityGroupEgress",                  # remove o egress padrao do SG novo e regras
      "ec2:ModifySecurityGroupRules",                   # update in-place de regras
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress", # descricao das regras de entrada
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",  # descricao das regras de saida
      "ec2:CreateTags",                                 # tags e default_tags
      "ec2:DeleteTags",                                 # update de tags
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "Rds"
    effect    = "Allow"
    resources = [format("${local.regional_prefix}:*", "rds")]
    actions = [
      "rds:CreateDBInstance",       # instancia PostgreSQL
      "rds:ModifyDBInstance",       # update in-place da instancia
      "rds:DeleteDBInstance",       # destroy da instancia
      "rds:CreateDBSnapshot",       # snapshot final quando skip_final_snapshot = false
      "rds:CreateDBSubnetGroup",    # subnet group
      "rds:ModifyDBSubnetGroup",    # update do subnet group
      "rds:DeleteDBSubnetGroup",    # destroy do subnet group
      "rds:AddTagsToResource",      # tags
      "rds:RemoveTagsFromResource", # tags
      "rds:ListTagsForResource",    # refresh de tags da instancia e do subnet group no apply
      "rds:DescribeDBInstances",    # refresh da instancia
      "rds:DescribeDBSubnetGroups", # refresh do subnet group
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # manage_master_user_password: o usuario que cria a instancia precisa destas permissoes
  # (https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html).
  statement {
    sid    = "RdsManagedSecret"
    effect = "Allow"
    resources = [
      format("${local.regional_prefix}:secret:rds!*", "secretsmanager"),
      format("${local.regional_prefix}:key/*", "kms"),
    ]
    actions = [
      "secretsmanager:CreateSecret", # RDS cria o segredo da senha master
      "secretsmanager:TagResource",  # tags do segredo
      "kms:DescribeKey",             # descreve a chave aws/secretsmanager
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "Ecs"
    effect    = "Allow"
    resources = [format("${local.regional_prefix}:*", "ecs")]
    actions = [
      "ecs:CreateCluster",         # cluster
      "ecs:UpdateCluster",         # update do cluster
      "ecs:UpdateClusterSettings", # containerInsights
      "ecs:DeleteCluster",         # destroy do cluster
      "ecs:CreateService",         # service
      "ecs:UpdateService",         # update do service
      "ecs:DeleteService",         # destroy do service
      "ecs:TagResource",           # tags
      "ecs:UntagResource",         # tags
      "ecs:ListTagsForResource",   # tags no refresh
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # DescribeLogGroups so aceita o ARN generico de log groups.
  statement {
    sid       = "LogsDescribe"
    effect    = "Allow"
    resources = [format("${local.regional_prefix}:log-group:*", "logs")]
    actions   = ["logs:DescribeLogGroups"] # refresh do log group

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "LogsProjectGroups"
    effect    = "Allow"
    resources = [format("${local.regional_prefix}:log-group:/ecs/${var.project_name}-*", "logs")]
    actions = [
      "logs:CreateLogGroup",        # log group /ecs/<service>
      "logs:DeleteLogGroup",        # destroy do log group
      "logs:PutRetentionPolicy",    # retencao dos logs
      "logs:DeleteRetentionPolicy", # update da retencao
      "logs:TagResource",           # tags
      "logs:UntagResource",         # tags
      "logs:ListTagsForResource",   # tags no refresh
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "CloudMap"
    effect    = "Allow"
    resources = [format("${local.regional_prefix}:*", "servicediscovery")]
    actions = [
      "servicediscovery:CreatePrivateDnsNamespace", # namespace privado
      "servicediscovery:DeleteNamespace",           # destroy do namespace
      "servicediscovery:CreateService",             # servico SRV
      "servicediscovery:UpdateService",             # update do servico
      "servicediscovery:DeleteService",             # destroy do servico
      "servicediscovery:TagResource",               # tags
      "servicediscovery:UntagResource",             # tags
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # O namespace privado do Cloud Map cria e remove uma zona hospedada privada (Route 53 e global,
  # sem aws:RequestedRegion). Resource "*": CreateHostedZone, GetChange e as leituras de zona do
  # Route 53 NAO suportam permissao por recurso e exigem "*" (doc Route 53: "This action does not
  # support resource-level permissions. Policies granting access must specify * in the resource").
  # A zona ainda nao existe no momento do CreateHostedZone, entao nao ha ARN a restringir.
  statement {
    sid       = "CloudMapHostedZone"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "route53:CreateHostedZone",      # zona privada do namespace
      "route53:DeleteHostedZone",      # destroy da zona
      "route53:GetHostedZone",         # leitura da zona
      "route53:GetChange",             # espera a propagacao
      "route53:ListHostedZonesByName", # exigida pelo CreatePrivateDnsNamespace (doc Cloud Map)
      "route53:ListTagsForResource",   # tags da zona
      "route53:ChangeTagsForResource", # tags da zona no create/update
    ]
  }

  statement {
    sid    = "ApiGateway"
    effect = "Allow"
    actions = [
      "apigateway:GET",           # leitura no refresh
      "apigateway:POST",          # cria API, VPC link, integracao, rota e estagio
      "apigateway:PUT",           # update
      "apigateway:PATCH",         # update de API, integracao, rota e estagio
      "apigateway:DELETE",        # destroy
      "apigateway:TagResource",   # tags do VPC link e do estagio (acao propria, nao coberta por PUT)
      "apigateway:UntagResource", # remocao de tags no update/destroy
    ]
    resources = [
      "${local.apigateway_arn}/apis",
      "${local.apigateway_arn}/apis/*",
      "${local.apigateway_arn}/vpclinks",
      "${local.apigateway_arn}/vpclinks/*",
      "${local.apigateway_arn}/tags/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # O Application Auto Scaling cria e atualiza os alarmes do target tracking em nome do chamador.
  statement {
    sid    = "AlarmsTargetTrackingAndStack"
    effect = "Allow"
    resources = [
      format("${local.regional_prefix}:alarm:TargetTracking-*", "cloudwatch"),
      format("${local.regional_prefix}:alarm:${var.project_name}-*", "cloudwatch"),
    ]
    actions = [
      "cloudwatch:PutMetricAlarm",      # alarmes da stack e do target tracking
      "cloudwatch:DeleteAlarms",        # destroy dos alarmes
      "cloudwatch:TagResource",         # tags
      "cloudwatch:UntagResource",       # tags
      "cloudwatch:ListTagsForResource", # tags no refresh
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

}

# Segunda policy do gha-infra: IAM do projeto, leitura do ECR e state. Separada da primeira porque
# uma policy gerenciada aceita no maximo 6.144 caracteres (sem espacos) e as duas somadas passam disso.
data "aws_iam_policy_document" "infra_iam_state" {
  # IAM limitado ao prefixo do projeto. As roles gha-* nao casam com o prefixo: o gha-infra nao
  # edita as proprias roles nem as dos outros workflows.
  statement {
    sid       = "IamProjectRoles"
    effect    = "Allow"
    resources = [local.project_role_arn]
    actions = [
      "iam:CreateRole",                  # roles de execucao e da task
      "iam:DeleteRole",                  # destroy das roles
      "iam:GetRole",                     # refresh
      "iam:UpdateAssumeRolePolicy",      # trust policy
      "iam:TagRole",                     # tags
      "iam:UntagRole",                   # tags
      "iam:ListRoleTags",                # tags no refresh
      "iam:ListRolePolicies",            # refresh
      "iam:ListAttachedRolePolicies",    # refresh
      "iam:ListInstanceProfilesForRole", # refresh de aws_iam_role
    ]
  }

  # So anexa/desanexa policies do proprio projeto (evita anexar AdministratorAccess).
  statement {
    sid       = "IamAttachProjectPolicies"
    effect    = "Allow"
    resources = [local.project_role_arn]
    actions = [
      "iam:AttachRolePolicy", # anexa a policy de menor privilegio
      "iam:DetachRolePolicy", # destroy do anexo
    ]

    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values   = [local.project_policy_arn]
    }
  }

  statement {
    sid       = "IamProjectPolicies"
    effect    = "Allow"
    resources = [local.project_policy_arn]
    actions = [
      "iam:CreatePolicy",        # policies das roles do projeto
      "iam:DeletePolicy",        # destroy
      "iam:GetPolicy",           # refresh
      "iam:GetPolicyVersion",    # refresh
      "iam:ListPolicyVersions",  # refresh
      "iam:CreatePolicyVersion", # update da policy
      "iam:DeletePolicyVersion", # limpeza de versoes
      "iam:TagPolicy",           # tags
      "iam:UntagPolicy",         # tags
      "iam:ListPolicyTags",      # tags no refresh
    ]
  }

  statement {
    sid       = "IamPassProjectRolesToEcs"
    effect    = "Allow"
    actions   = ["iam:PassRole"] # o service e a task definition usam as roles do projeto
    resources = [local.project_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Primeiro uso de ECS, Application Auto Scaling, RDS e API Gateway na conta.
  statement {
    sid       = "IamServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"] # cria as roles de servico se ainda nao existirem
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "ecs.application-autoscaling.amazonaws.com",
        "rds.amazonaws.com",
        "ops.apigateway.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "EcrReadRepository"
    effect = "Allow"
    # data.aws_ecr_repository: o provider aws 6.x tambem chama DescribeImages ao ler o repositorio
    # (a stack nao cria o repositorio, so o referencia). Restrito ao ARN do repo (least-privilege).
    actions   = ["ecr:DescribeRepositories", "ecr:ListTagsForResource", "ecr:DescribeImages"]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"] # backend S3 lista o bucket
    resources = [local.state_bucket_arn]
  }

  statement {
    sid    = "StateObject"
    effect = "Allow"
    actions = [
      "s3:GetObject", # le o state
      "s3:PutObject", # grava o state
    ]
    resources = [local.state_object_arn]
  }

  statement {
    sid    = "StateLockObject"
    effect = "Allow"
    actions = [
      "s3:GetObject",    # le o lock
      "s3:PutObject",    # cria o lock
      "s3:DeleteObject", # libera o lock
    ]
    resources = [local.state_lock_arn]
  }
}

# ---------------------------------------------------------------------------------------------
# gha-eks-lab: aplica e destroi SO o root eks-lab (EKS, node group, add-ons, Pod Identity, regras proprias do lab).
# Roda no environment "eks-lab" (sem aprovacao: o destroy agendado por TTL precisa rodar sozinho). Nao opera a stack
# principal. Policy dividida em duas (limite de 6.144 caracteres por policy gerenciada): esta e a de IAM.
# ---------------------------------------------------------------------------------------------
locals {
  eks_lab_state_key = replace(var.state_key, "terraform.tfstate", "eks-lab/terraform.tfstate")
  eks_lab_cluster   = "${var.project_name}-*-eks"
  eks_prefix        = "arn:${local.partition}:eks:${var.region}:${local.account_id}"
  eks_lab_role_arn  = "arn:${local.partition}:iam::${local.account_id}:role/${var.project_name}-*-eks-*"
  eks_lab_policy    = "arn:${local.partition}:iam::${local.account_id}:policy/${var.project_name}-*-eks-*"
}

data "aws_iam_policy_document" "eks_lab" {
  # Resource "*": Describe* e List* nao aceitam ARN.
  statement {
    sid       = "DescribeRegional"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "eks:Describe*",                                       # refresh do cluster, node group, add-ons e Pod Identity
      "eks:List*",                                           # listagens (o destroy agendado procura clusters vencidos por tag)
      "ec2:Describe*",                                       # refresh de VPC, subnets, SGs, ENIs e instancias dos nos
      "elasticloadbalancing:DescribeLoadBalancers",          # data.aws_lb e a espera do NLB criado pelo controller
      "elasticloadbalancing:DescribeLoadBalancerAttributes", # data.aws_lb (medido no log do provider 6.68.0, janela 3)
      "elasticloadbalancing:DescribeListeners",              # data.aws_lb_listener (ARN do listener do NLB)
      "elasticloadbalancing:DescribeTags",                   # data.aws_lb por tag service.k8s.aws/stack
      "iam:ListRolePolicies",                                # refresh das roles do lab
      "iam:ListAttachedRolePolicies",                        # refresh dos anexos das roles do lab
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid    = "EksLabCluster"
    effect = "Allow"
    resources = [
      "${local.eks_prefix}:cluster/${local.eks_lab_cluster}",
      "${local.eks_prefix}:nodegroup/${local.eks_lab_cluster}/*",
      "${local.eks_prefix}:addon/${local.eks_lab_cluster}/*",
      "${local.eks_prefix}:access-entry/${local.eks_lab_cluster}/*",
      "${local.eks_prefix}:podidentityassociation/${local.eks_lab_cluster}/*",
    ]
    actions = [
      "eks:CreateCluster",                # cluster do lab
      "eks:DeleteCluster",                # destroy do lab
      "eks:UpdateClusterConfig",          # ajustes do cluster
      "eks:UpdateClusterVersion",         # upgrade_policy e versao
      "eks:TagResource",                  # tags (Project, TTL...)
      "eks:UntagResource",                # remocao de tags
      "eks:CreateNodegroup",              # managed node group
      "eks:DeleteNodegroup",              # destroy do node group
      "eks:UpdateNodegroupConfig",        # escala dos nos
      "eks:UpdateNodegroupVersion",       # versao dos nos
      "eks:CreateAddon",                  # vpc-cni, kube-proxy, coredns, pod identity agent, metrics-server
      "eks:UpdateAddon",                  # versao dos add-ons
      "eks:DeleteAddon",                  # destroy dos add-ons
      "eks:CreateAccessEntry",            # acesso de administrador por IAM (authentication_mode = API)
      "eks:UpdateAccessEntry",            # ajuste do access entry
      "eks:DeleteAccessEntry",            # destroy do access entry
      "eks:AssociateAccessPolicy",        # politica de acesso do administrador
      "eks:DisassociateAccessPolicy",     # destroy da associacao
      "eks:CreatePodIdentityAssociation", # Pod Identity do controller e da app
      "eks:UpdatePodIdentityAssociation", # ajuste da associacao
      "eks:DeletePodIdentityAssociation", # destroy da associacao
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # Regras e tags PROPRIAS do lab (resource "*" nas SGs porque a SG do cluster nasce com o cluster): so reescrevem
  # regras e tags, nao criam nem apagam SG.
  statement {
    sid       = "Ec2LabRulesAndTags"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",              # regra do RDS e dos pods (aws_vpc_security_group_ingress_rule)
      "ec2:AuthorizeSecurityGroupEgress",               # saida do VPC Link ate o NLB
      "ec2:RevokeSecurityGroupIngress",                 # destroy das regras
      "ec2:RevokeSecurityGroupEgress",                  # destroy das regras
      "ec2:ModifySecurityGroupRules",                   # update in-place de regras
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress", # descricao das regras de entrada
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",  # descricao das regras de saida
      "ec2:CreateTags",                                 # aws_ec2_tag (kubernetes.io/role/internal-elb) e tags do cluster
      "ec2:DeleteTags",                                 # remove a tag no destroy
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # Rotas do lab na HTTP API da stack principal: integracao e rota ANY /eks. O ID da API muda a cada apply da stack.
  statement {
    sid    = "ApiGatewayEksRoutes"
    effect = "Allow"
    actions = [
      "apigateway:GET",    # leitura no refresh
      "apigateway:POST",   # cria integracao e rota
      "apigateway:PATCH",  # update da integracao e da rota
      "apigateway:DELETE", # destroy da integracao e da rota
    ]
    resources = [
      "${local.apigateway_arn}/apis",
      "${local.apigateway_arn}/apis/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # Precaucao (nao comprovado como necessario): a integracao usa o VPC link da stack principal; so leitura, sem POST/DELETE.
  statement {
    sid       = "ApiGatewayReadVpcLink"
    effect    = "Allow"
    actions   = ["apigateway:GET"]
    resources = ["${local.apigateway_arn}/vpclinks/*"]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"] # backend S3 lista o bucket
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "EksLabState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"] # le e grava o state PROPRIO do lab
    resources = ["${local.state_bucket_arn}/${local.eks_lab_state_key}"]
  }

  statement {
    sid       = "EksLabStateLock"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"] # trava nativa (use_lockfile): <key>.tflock
    resources = ["${local.state_bucket_arn}/${local.eks_lab_state_key}.tflock"]
  }

  statement {
    sid       = "ReadMainState"
    effect    = "Allow"
    actions   = ["s3:GetObject"] # terraform_remote_state da stack principal: SOMENTE leitura
    resources = [local.state_object_arn]
  }
}

data "aws_iam_policy_document" "eks_lab_iam" {
  # So roles e policies do lab (prefixo <projeto>-<env>-eks-). Nao alcanca as roles gha-*, nem as da stack principal.
  statement {
    sid       = "IamEksLabRoles"
    effect    = "Allow"
    resources = [local.eks_lab_role_arn]
    actions = [
      "iam:CreateRole",                  # roles do cluster, dos nos e do Pod Identity
      "iam:DeleteRole",                  # destroy
      "iam:GetRole",                     # refresh
      "iam:UpdateAssumeRolePolicy",      # trust policy
      "iam:TagRole",                     # tags
      "iam:UntagRole",                   # tags
      "iam:ListRoleTags",                # tags no refresh
      "iam:ListInstanceProfilesForRole", # refresh de aws_iam_role
    ]
  }

  # Anexa so as politicas gerenciadas da AWS necessarias ao EKS e as politicas do proprio lab (evita AdministratorAccess).
  statement {
    sid       = "IamAttachEksLabPolicies"
    effect    = "Allow"
    resources = [local.eks_lab_role_arn]
    actions = [
      "iam:AttachRolePolicy", # anexa a politica
      "iam:DetachRolePolicy", # destroy do anexo
    ]

    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = [
        local.eks_lab_policy,
        "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
        "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
        "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
        "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
      ]
    }
  }

  statement {
    sid       = "IamEksLabPolicies"
    effect    = "Allow"
    resources = [local.eks_lab_policy]
    actions = [
      "iam:CreatePolicy",        # policies do controller e da app
      "iam:DeletePolicy",        # destroy
      "iam:GetPolicy",           # refresh
      "iam:GetPolicyVersion",    # refresh
      "iam:ListPolicyVersions",  # refresh
      "iam:CreatePolicyVersion", # update da policy
      "iam:DeletePolicyVersion", # limpeza de versoes
      "iam:TagPolicy",           # tags
      "iam:UntagPolicy",         # tags
      "iam:ListPolicyTags",      # tags no refresh
    ]
  }

  statement {
    sid       = "IamPassEksLabRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"] # o EKS e o node group usam as roles do lab
    resources = [local.eks_lab_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com", "ec2.amazonaws.com", "pods.eks.amazonaws.com"] # pods.*: Pod Identity (3o erro da janela 3)
    }
  }

  # O EKS confere se a role de servico do node group existe antes de criar o node group
  # (erro real da janela 3: "missing permissions for 'iam:GetRole'" em AWSServiceRoleForAmazonEKSNodegroup).
  statement {
    sid     = "IamReadServiceLinkedRolesEks"
    effect  = "Allow"
    actions = ["iam:GetRole"] # so leitura, so roles de servico
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*",
      # Role ainda inexistente: o IAM avalia o GetRole pelo ARN SEM o path (confirmado no simulador e no 2o erro da janela 3).
      "arn:${local.partition}:iam::${local.account_id}:role/AWSServiceRoleForAmazonEKS",
      "arn:${local.partition}:iam::${local.account_id}:role/AWSServiceRoleForAmazonEKSNodegroup",
      "arn:${local.partition}:iam::${local.account_id}:role/AWSServiceRoleForElasticLoadBalancing",
    ]
  }

  # Primeiro uso de EKS, node group e Elastic Load Balancing na conta.
  statement {
    sid       = "IamServiceLinkedRolesEks"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"] # cria as roles de servico se ainda nao existirem
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_policy" "eks_lab_iam" {
  name        = "gha-eks-lab-iam-policy"
  description = "gha-eks-lab: IAM do lab EKS (roles e policies <projeto>-*-eks-*)"
  policy      = data.aws_iam_policy_document.eks_lab_iam.json
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_lab_iam" {
  role       = module.role["gha-eks-lab"].role_name
  policy_arn = aws_iam_policy.eks_lab_iam.arn
}
