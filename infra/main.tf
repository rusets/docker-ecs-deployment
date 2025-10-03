terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
  backend "s3" {
    bucket         = "docker-ecs-deployment"
    key            = "ecs-demo/infra.tfstate"
    region         = "us-east-1"
    dynamodb_table = "docker-ecs-deployment"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

variable "project_name" {
  type        = string
  default     = "ecs-demo"
  description = "Project name prefix"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "desired_count" {
  type        = number
  default     = 0
  description = "0 = idle"
}

variable "task_cpu" {
  type    = string
  default = "256"
}

variable "task_memory" {
  type    = string
  default = "512"
}

variable "app_port" {
  type        = number
  default     = 80
  description = "Container port"
}

variable "ecr_repo_name" {
  type    = string
  default = "ecs-demo-app"
}

variable "enable_wake_api" {
  type    = bool
  default = true
}

variable "enable_auto_sleep" {
  type    = bool
  default = true
}

variable "sleep_after_minutes" {
  type    = number
  default = 5
}

locals {
  wake_zip_path  = "${path.module}/wake.zip"
  wake_zip_hash  = try(filebase64sha256(local.wake_zip_path), "")

  sleep_zip_path = "${path.module}/sleep.zip"
  sleep_zip_hash = try(filebase64sha256(local.sleep_zip_path), "")
}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.2.0"

  name                 = var.project_name
  cidr                 = var.vpc_cidr
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets       = var.public_subnets
  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_security_group" "service" {
  name_prefix = "${var.project_name}-svc-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = var.project_name }
}

resource "aws_ecr_repository" "this" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration     { encryption_type = "AES256" }

  tags = { Project = var.project_name }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Expire untagged after 7 days",
        selection    = {
          tagStatus   = "untagged",
          countType   = "sinceImagePushed",
          countUnit   = "days",
          countNumber = 7
        },
        action = { type = "expire" }
      },
      {
        rulePriority = 2,
        description  = "Keep last 10 latest",
        selection    = {
          tagStatus     = "tagged",
          tagPrefixList = ["latest"],
          countType     = "imageCountMoreThan",
          countNumber   = 10
        },
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 3
  tags              = { Project = var.project_name }
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = aws_iam_role.ecs_execution_role.assume_role_policy
  tags               = { Project = var.project_name }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "app",
      image     = "${aws_ecr_repository.this.repository_url}:latest",
      essential = true,
      portMappings = [{
        containerPort = var.app_port,
        hostPort      = var.app_port,
        protocol      = "tcp"
      }],
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name,
          awslogs-region        = var.region,
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  tags = { Project = var.project_name }
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.service.id]
  assign_public_ip = true
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Project = var.project_name }
}

resource "aws_iam_role" "wake_role" {
  count = var.enable_wake_api ? 1 : 0
  name  = "wake-ecs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "wake_policy" {
  count = var.enable_wake_api ? 1 : 0
  name  = "wake-ecs-inline"
  role  = aws_iam_role.wake_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["ecs:UpdateService","ecs:DescribeServices","ecs:ListTasks","ecs:DescribeTasks"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:DescribeNetworkInterfaces"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "*" }
    ]
  })
}

resource "aws_lambda_function" "wake" {
  count         = var.enable_wake_api ? 1 : 0
  function_name = "${var.project_name}-wake"
  role          = aws_iam_role.wake_role[0].arn
  runtime       = "python3.12"
  handler       = "lambda_function.handler"
  filename         = local.wake_zip_path
  source_code_hash = local.wake_zip_hash
  timeout = 29
  environment {
    variables = {
      CLUSTER_NAME = aws_ecs_cluster.this.name
      SERVICE_NAME = aws_ecs_service.app.name
      APP_PORT     = tostring(var.app_port)
      WAIT_MS      = "120000"
    }
  }
  depends_on = [aws_iam_role_policy.wake_policy]
}

resource "aws_apigatewayv2_api" "wake" {
  count         = var.enable_wake_api ? 1 : 0
  name          = "${var.project_name}-wake"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "wake" {
  count                  = var.enable_wake_api ? 1 : 0
  api_id                 = aws_apigatewayv2_api.wake[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.wake[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "wake" {
  count     = var.enable_wake_api ? 1 : 0
  api_id    = aws_apigatewayv2_api.wake[0].id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.wake[0].id}"
}

resource "aws_lambda_permission" "apigw_invoke" {
  count         = var.enable_wake_api ? 1 : 0
  statement_id  = "AllowInvokeByAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wake[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake[0].execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "wake" {
  count       = var.enable_wake_api ? 1 : 0
  api_id      = aws_apigatewayv2_api.wake[0].id
  name        = "$default"
  auto_deploy = true
}

resource "aws_iam_role" "autosleep_role" {
  count = var.enable_auto_sleep ? 1 : 0
  name  = "${var.project_name}-autosleep-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "autosleep_policy" {
  count = var.enable_auto_sleep ? 1 : 0
  name  = "${var.project_name}-autosleep-inline"
  role  = aws_iam_role.autosleep_role[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["ecs:DescribeServices","ecs:ListTasks","ecs:DescribeTasks","ecs:UpdateService"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "*" }
    ]
  })
}

resource "aws_lambda_function" "autosleep" {
  count         = var.enable_auto_sleep ? 1 : 0
  function_name = "${var.project_name}-autosleep"
  role          = aws_iam_role.autosleep_role[0].arn
  runtime       = "python3.12"
  handler       = "auto_sleep.handler"
  filename         = local.sleep_zip_path
  source_code_hash = local.sleep_zip_hash
  timeout = 15
  environment {
    variables = {
      CLUSTER_NAME        = aws_ecs_cluster.this.name
      SERVICE_NAME        = aws_ecs_service.app.name
      SLEEP_AFTER_MINUTES = tostring(var.sleep_after_minutes)
    }
  }
  depends_on = [aws_iam_role_policy.autosleep_policy]
}

resource "aws_cloudwatch_event_rule" "autosleep" {
  count               = var.enable_auto_sleep ? 1 : 0
  name                = "${var.project_name}-autosleep"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "autosleep" {
  count     = var.enable_auto_sleep ? 1 : 0
  rule      = aws_cloudwatch_event_rule.autosleep[0].name
  target_id = "autosleep-lambda"
  arn       = aws_lambda_function.autosleep[0].arn
}

resource "aws_lambda_permission" "events_invoke_autosleep" {
  count         = var.enable_auto_sleep ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.autosleep[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.autosleep[0].arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.this.repository_url
}
output "cluster_name" {
  value = aws_ecs_cluster.this.name
}
output "service_name" {
  value = aws_ecs_service.app.name
}
output "region" {
  value = var.region
}
output "wake_url" {
  value       = try(aws_apigatewayv2_api.wake[0].api_endpoint, null)
  description = "Public wake URL"
}