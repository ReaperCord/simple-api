resource "aws_ecs_cluster" "this" {
  name = var.cluster_name
  tags = var.tags

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.service_name}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  tags                     = var.tags

  # Decisao 5: o pipeline registra as revisoes seguintes e o service ignora task_definition.
  # Sem skip_destroy o Terraform desregistraria a revisao antiga em um replace e o service
  # poderia ficar apontando para uma revisao INACTIVE.
  skip_destroy = true

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = var.environment_variables
      secrets     = var.secrets

      readonlyRootFilesystem = true
      stopTimeout            = var.stop_timeout

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:${var.container_port}/health || exit 1"]
        interval    = var.health_check_interval
        timeout     = var.health_check_timeout
        retries     = var.health_check_retries
        startPeriod = var.health_check_start_period
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name                               = var.service_name
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  # Registro SRV no Cloud Map (exigido pela integracao do API Gateway via VPC Link).
  dynamic "service_registries" {
    for_each = var.service_registry_arn == null ? [] : [1]
    content {
      registry_arn   = var.service_registry_arn
      container_name = var.container_name
      container_port = var.container_port
    }
  }

  # Alternativa ingress_mode = "alb" (nao instanciada na trilha principal).
  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  tags = var.tags

  # Regra 11 (04-terraform.md) + Decisao 5: o Terraform cria a revisao inicial; o pipeline
  # registra as seguintes e chama UpdateService, e o autoscaling controla desired_count.
  # Trade-off: mudar task_definition (env, CPU, memoria, healthCheck) ou desired_count pelo
  # Terraform NAO chega ao service depois da criacao; so um deploy pelo pipeline aplica.
  # Revise todo plan que mostre este service "must be replaced" antes do apply.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
