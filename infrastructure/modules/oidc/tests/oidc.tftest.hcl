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
  github_owner_id    = "1111"
  github_repo_id     = "2222"
  project_name       = "simple-api"
  region             = "us-east-1"
  state_bucket_name  = "test-tfstate"
  state_key          = "simple-api/dev/terraform.tfstate"
  ecr_repository_arn = "arn:aws:ecr:us-east-1:000000000000:repository/simple-api"
  ecs_cluster_name   = "simple-api-dev"
  ecs_service_name   = "simple-api-dev"
  task_role_names    = ["simple-api-dev-ecs-exec", "simple-api-dev-ecs-task"]
}

# Dois sub por role (lista fechada): por NOME e IMUTAVEL (repo:OWNER@OWNER-ID/REPO@REPO-ID:<ctx>),
# conforme 03-devsecops.md e locals do modulo. So as tres roles (nao existe gha-eks-lab).
run "sub_exatos_e_sem_gha_eks_lab" {
  command = plan

  assert {
    condition = output.role_subjects == {
      "gha-plan" = [
        "repo:test-owner/simple-api:pull_request",
        "repo:test-owner@1111/simple-api@2222:pull_request",
      ]
      "gha-deploy" = [
        "repo:test-owner/simple-api:environment:deploy",
        "repo:test-owner@1111/simple-api@2222:environment:deploy",
      ]
      "gha-infra" = [
        "repo:test-owner/simple-api:environment:infra",
        "repo:test-owner@1111/simple-api@2222:environment:infra",
      ]
    }
    error_message = "Cada role deve aceitar exatamente o sub por nome e o sub imutavel de pull_request, environment:deploy e environment:infra."
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

# A trust policy de cada role: aud exato (StringEquals) e sub numa lista fechada (StringLike, sem curinga).
run "trust_policy_com_aud_e_sub_exatos" {
  command = apply

  assert {
    condition = alltrue([
      for role, doc in output.trust_policies :
      jsondecode(doc).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(doc).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
      !can(jsondecode(doc).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) &&
      jsondecode(doc).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == output.role_subjects[role]
    ])
    error_message = "Cada trust policy deve ter aud=sts.amazonaws.com (StringEquals) e exatamente os dois sub da role em StringLike."
  }

  assert {
    condition     = alltrue([for role, subs in output.role_subjects : alltrue([for sub in subs : !strcontains(sub, "*")])])
    error_message = "Nenhum sub pode conter curinga."
  }

  assert {
    condition     = jsondecode(output.trust_policies["gha-plan"]).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == ["repo:test-owner/simple-api:pull_request", "repo:test-owner@1111/simple-api@2222:pull_request"]
    error_message = "gha-plan deve aceitar so o sub pull_request (por nome e imutavel)."
  }

  assert {
    condition     = jsondecode(output.trust_policies["gha-deploy"]).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == ["repo:test-owner/simple-api:environment:deploy", "repo:test-owner@1111/simple-api@2222:environment:deploy"]
    error_message = "gha-deploy deve aceitar so o sub environment:deploy (por nome e imutavel)."
  }

  assert {
    condition     = jsondecode(output.trust_policies["gha-infra"]).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"] == ["repo:test-owner/simple-api:environment:infra", "repo:test-owner@1111/simple-api@2222:environment:infra"]
    error_message = "gha-infra deve aceitar so o sub environment:infra (por nome e imutavel)."
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

run "github_owner_id_nao_numerico_falha" {
  command = plan

  variables {
    github_owner_id = "12*"
  }

  expect_failures = [var.github_owner_id]
}

run "github_repo_id_nao_numerico_falha" {
  command = plan

  variables {
    github_repo_id = "abc"
  }

  expect_failures = [var.github_repo_id]
}
