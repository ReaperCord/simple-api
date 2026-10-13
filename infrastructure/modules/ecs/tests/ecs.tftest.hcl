mock_provider "aws" {}

variables {
  cluster_name       = "test-cluster"
  service_name       = "test-service"
  region             = "test-region"
  container_name     = "app"
  container_image    = "registry.test/app:tag"
  execution_role_arn = "arn:aws:iam:::role/test-exec"
  subnet_ids         = ["subnet-mock-a", "subnet-mock-b"]
  security_group_ids = ["sg-mock"]
}

# Defaults: ARM64, 512 de CPU, 1024 MiB, skip_destroy, healthCheck, stopTimeout, circuit breaker.
run "defaults_da_trilha" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "ARM64"
    error_message = "cpu_architecture default deve ser ARM64."
  }

  assert {
    condition     = aws_ecs_task_definition.this.runtime_platform[0].operating_system_family == "LINUX"
    error_message = "operating_system_family deve ser LINUX."
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "512" && aws_ecs_task_definition.this.memory == "1024"
    error_message = "Defaults devem ser cpu=512 e memory=1024."
  }

  assert {
    condition     = aws_ecs_task_definition.this.skip_destroy == true
    error_message = "skip_destroy deve ser true (Decisao 5)."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.command[1] == "wget -qO- http://localhost:3000/health || exit 1"
    error_message = "healthCheck deve consultar /health na porta do container."
  }

  assert {
    condition = (
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.interval == 30 &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.timeout == 5 &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.retries == 3 &&
      jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.startPeriod == 15
    )
    error_message = "Defaults do healthCheck: interval 30, timeout 5, retries 3, startPeriod 15."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].stopTimeout == 30
    error_message = "stopTimeout default deve ser 30."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].readonlyRootFilesystem == true
    error_message = "readonlyRootFilesystem deve ser true."
  }

  assert {
    condition = (
      aws_ecs_service.this.deployment_circuit_breaker[0].enable == true &&
      aws_ecs_service.this.deployment_circuit_breaker[0].rollback == true
    )
    error_message = "Circuit breaker com rollback deve estar habilitado."
  }

  assert {
    condition = (
      aws_ecs_service.this.deployment_minimum_healthy_percent == 100 &&
      aws_ecs_service.this.deployment_maximum_percent == 200
    )
    error_message = "Defaults de deploy: 100/200."
  }

  assert {
    condition     = length(aws_ecs_service.this.service_registries) == 0
    error_message = "Sem service_registry_arn nao deve haver service_registries."
  }
}

run "service_registries_quando_informado" {
  command = plan

  variables {
    service_registry_arn = "arn:aws:servicediscovery:::service/test-srv"
  }

  assert {
    condition     = length(aws_ecs_service.this.service_registries) == 1
    error_message = "Com service_registry_arn deve haver 1 service_registries."
  }

  assert {
    condition = (
      one(aws_ecs_service.this.service_registries).registry_arn == "arn:aws:servicediscovery:::service/test-srv" &&
      one(aws_ecs_service.this.service_registries).container_name == "app" &&
      one(aws_ecs_service.this.service_registries).container_port == 3000
    )
    error_message = "service_registries deve usar registry_arn, container_name e container_port."
  }
}

run "cpu_architecture_x86_64_aceita" {
  command = plan

  variables {
    cpu_architecture = "X86_64"
  }

  assert {
    condition     = aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "X86_64"
    error_message = "cpu_architecture X86_64 deve chegar a task definition."
  }
}

run "cpu_architecture_invalida_falha" {
  command = plan

  variables {
    cpu_architecture = "ARM32"
  }

  expect_failures = [var.cpu_architecture]
}

# 0,5 vCPU + 512 MiB e invalido no Fargate.
run "combinacao_cpu_memoria_invalida_falha" {
  command = plan

  variables {
    task_cpu    = 512
    task_memory = 512
  }

  expect_failures = [var.task_memory]
}
