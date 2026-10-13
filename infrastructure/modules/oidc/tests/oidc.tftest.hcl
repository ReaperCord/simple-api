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

  # O JSON do policy document e calculado pelo provider; no mock precisa ser um JSON valido.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::000000000000:oidc-provider/token.actions.githubusercontent.com"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::000000000000:role/mock"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::000000000000:policy/mock"
    }
  }
}

variables {
  github_owner       = "test-owner"
  github_repo        = "simple-api"
  project_name       = "simple-api"
  region             = "us-east-1"
  state_bucket_name  = "test-tfstate"
  state_key          = "simple-api/dev/terraform.tfstate"
  ecr_repository_arn = "arn:aws:ecr:us-east-1:000000000000:repository/simple-api"
  ecs_cluster_name   = "simple-api-dev"
  ecs_service_name   = "simple-api-dev"
  task_role_names    = ["simple-api-dev-ecs-exec", "simple-api-dev-ecs-task"]
}

# Os tres sub exatos de 03-devsecops.md, e so as tres roles (nao existe gha-eks-lab).
run "sub_exatos_e_sem_gha_eks_lab" {
  command = plan

  assert {
    condition = output.role_subjects == {
      "gha-plan"   = "repo:test-owner/simple-api:pull_request"
      "gha-deploy" = "repo:test-owner/simple-api:environment:deploy"
      "gha-infra"  = "repo:test-owner/simple-api:environment:infra"
    }
    error_message = "Os sub devem ser exatamente pull_request, environment:deploy e environment:infra."
  }

  assert {
    condition     = toset(output.role_names) == toset(["gha-plan", "gha-deploy", "gha-infra"])
    error_message = "Devem existir somente gha-plan, gha-deploy e gha-infra."
  }

  assert {
    condition     = length([for n in output.role_names : n if can(regex("eks", n))]) == 0
    error_message = "Nao pode existir role gha-eks-lab neste modulo."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.client_id_list == toset(["sts.amazonaws.com"])
    error_message = "client_id_list deve ser so sts.amazonaws.com."
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com"
    error_message = "A URL do provider deve ser a do GitHub Actions."
  }
}

# A trust policy de cada role usa aud e sub exatos (StringEquals, sem curinga).
run "trust_policy_com_aud_e_sub_exatos" {
  command = apply

  assert {
    condition = alltrue([
      for role, doc in output.trust_policies :
      jsondecode(doc).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(doc).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
      jsondecode(doc).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == output.role_subjects[role] &&
      !can(jsondecode(doc).Statement[0].Condition.StringLike)
    ])
    error_message = "Cada trust policy deve ter aud=sts.amazonaws.com e o sub exato da role, via StringEquals."
  }

  assert {
    condition     = alltrue([for role, sub in output.role_subjects : !strcontains(sub, "*")])
    error_message = "Nenhum sub pode conter curinga."
  }

  assert {
    condition     = jsondecode(output.trust_policies["gha-plan"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:test-owner/simple-api:pull_request"
    error_message = "gha-plan deve aceitar so o sub pull_request."
  }

  assert {
    condition     = jsondecode(output.trust_policies["gha-deploy"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:test-owner/simple-api:environment:deploy"
    error_message = "gha-deploy deve aceitar so o sub environment:deploy."
  }

  assert {
    condition     = jsondecode(output.trust_policies["gha-infra"]).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:test-owner/simple-api:environment:infra"
    error_message = "gha-infra deve aceitar so o sub environment:infra."
  }
}

run "github_owner_com_curinga_falha" {
  command = plan

  variables {
    github_owner = "test-*"
  }

  expect_failures = [var.github_owner]
}

run "github_repo_com_curinga_falha" {
  command = plan

  variables {
    github_repo = "simple-api*"
  }

  expect_failures = [var.github_repo]
}
