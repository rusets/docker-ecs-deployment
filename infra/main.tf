#############################################
# Terraform backend + providers
#############################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # AWS provider (v5+ is fine)
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }

  # Remote state in S3 with DynamoDB state locking
  backend "s3" {
    bucket         = "docker-ecs-deployment"       # S3 bucket for tfstate
    key            = "ecs-demo/infra.tfstate"      # Key (path) inside the bucket
    region         = "us-east-1"                   # Bucket region
    dynamodb_table = "docker-ecs-deployment"       # Table for state locking
    encrypt        = true                          # Server-side encryption for state
  }
}

# Default AWS region comes from var.region
provider "aws" {
  region = var.region
}

#############################################
# Variables (tune cost/perf here)
#############################################

# Human-friendly project prefix used for names/tags of AWS resources
variable "project_name" {
  type        = string
  default     = "ecs-demo"
  description = "Name prefix applied to AWS resources (cluster/service/roles/etc.)."
}

# Primary region
variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources."
}

# Simple /16 VPC CIDR with two public /24 subnets (no NAT, public-only)
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}

# Desired count of ECS tasks. Set to 0 to pay $0 when idle (Fargate).
variable "desired_count" {
  type        = number
  default     = 0
  description = "ECS desired tasks. 0 = fully idle (no Fargate charge)."
}

# Fargate task size (CPU units). 256 = 0.25 vCPU.
variable "task_cpu" {
  type    = string
  default = "256"
}

# Fargate task memory (MiB). 512 = 0.5GB.
variable "task_memory" {
  type    = string
  default = "512"
}

# Container port exposed by the app (Express listens on :80)
variable "app_port" {
  type        = number
  default     = 80
  description = "Application container port exposed via awsvpc ENI."
}

# ECR repo name (holds docker images for the app)
variable "ecr_repo_name" {
  type    = string
  default = "ecs-demo-app"
}

# Feature flags: HTTP “wake” endpoint (API GW + Lambda)
variable "enable_wake_api" {
  type    = bool
  default = true
}

# Feature flags: Auto-sleep Lambda (EventBridge cron each minute)
variable "enable_auto_sleep" {
  type    = bool
  default = true
}

# Auto-sleep delay (minutes since last RUNNING task)
variable "sleep_after_minutes" {
  type    = number
  default = 5
}

#############################################
# Local paths & hashes for Lambda packages
# (zip files must exist next to this main.tf)
#############################################

locals {
  # Wake Lambda zip file path and content hash
  wake_zip_path  = "${path.module}/wake.zip"
  wake_zip_hash  = try(filebase64sha256(local.wake_zip_path), "")

  # Auto-sleep Lambda zip file path and content hash
  sleep_zip_path = "${path.module}/sleep.zip"
  sleep_zip_hash = try(filebase64sha256(local.sleep_zip_path), "")
}

#############################################
# Networking (VPC with two PUBLIC subnets)
#############################################

# Discover at least two AZs in the region
data "aws_availability_zones" "available" {}

# Minimal-cost VPC: only public subnets, no NAT
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.2.0"

  name                 = var.project_name
  cidr                 = var.vpc_cidr
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets       = var.public_subnets
  enable_nat_gateway   = false                     # Save cost: no NAT
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Security group allowing HTTP inbound and all outbound
resource "aws_security_group" "service" {
  name_prefix = "${var.project_name}-svc-"
  vpc_id      = module.vpc.vpc_id

  # Inbound: world -> app port
  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: allow everything (needed for ECR pull, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = var.project_name }
}

#############################################
# ECR (repo + lifecycle policy)
#############################################

resource "aws_ecr_repository" "this" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"                 # allow retagging 'latest'
  force_delete         = true                      # destroy even if images remain

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration     { encryption_type = "AES256" }

  tags = { Project = var.project_name }
}

# Keep it clean: expire untagged, trim 'latest' images
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
        description  = "Keep last 10 'latest' images",
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

#############################################
# CloudWatch Logs for ECS tasks
#############################################

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 3                           # short retention to save cost
  tags              = { Project = var.project_name }
}

#############################################
# ECS Cluster, Roles, Task Definition, Service
#############################################

# Plain ECS cluster
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
}

# Execution role: ECS agent needs this to pull from ECR, write logs
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

# Attach AWS-managed policy for ECS execution
resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role (app’s own AWS permissions). Empty by default.
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = aws_iam_role.ecs_execution_role.assume_role_policy
  tags               = { Project = var.project_name }
}

# Fargate task definition (ARM64 to save cost on Graviton)
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  # Single container: pulls :latest tag from ECR repo
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
    cpu_architecture        = "ARM64"              # Graviton2/3 (cheaper)
  }

  tags = { Project = var.project_name }
}

# ECS service on Fargate with public IP (no ALB; connect directly to task ENI)
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count             # 0 by default (idle)
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true                       # attach public IP to task ENI
  }

  # Safer rolling update with circuit breaker auto-rollback
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Don’t recreate service on each TD revision; we update explicitly
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Project = var.project_name }
}

#############################################
# Wake-on-request: API Gateway (HTTP) + Lambda
# Hitting the URL scales service to 1 and redirects to task IP
#############################################

# Lambda execution role for "wake" (ECS read/update + Logs)
resource "aws_iam_role" "wake_role" {
  count = var.enable_wake_api ? 1 : 0
  name  = "wake-ecs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = var.project_name }
}

# Inline permissions for wake Lambda
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

# Wake Lambda (Python). Zip must exist: ./wake.zip (contains lambda_function.py)
resource "aws_lambda_function" "wake" {
  count         = var.enable_wake_api ? 1 : 0
  function_name = "${var.project_name}-wake"
  role          = aws_iam_role.wake_role[0].arn
  runtime       = "python3.12"
  handler       = "lambda_function.handler"

  filename         = local.wake_zip_path          # local path to zip
  source_code_hash = local.wake_zip_hash          # forces update on zip change

  timeout = 29                                    # ~30s hard limit on HTTP API
  environment {
    variables = {
      CLUSTER_NAME = aws_ecs_cluster.this.name
      SERVICE_NAME = aws_ecs_service.app.name
      APP_PORT     = tostring(var.app_port)
      WAIT_MS      = "120000"                     # total retry budget across refreshes
    }
  }
  depends_on = [aws_iam_role_policy.wake_policy]  # ensure policies exist first
}

# HTTP API for the wake endpoint (no custom domain here)
resource "aws_apigatewayv2_api" "wake" {
  count         = var.enable_wake_api ? 1 : 0
  name          = "${var.project_name}-wake"
  protocol_type = "HTTP"
}

# Proxy integration to Lambda (HTTP API v2)
resource "aws_apigatewayv2_integration" "wake" {
  count                  = var.enable_wake_api ? 1 : 0
  api_id                 = aws_apigatewayv2_api.wake[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.wake[0].invoke_arn
  payload_format_version = "2.0"
}

# Single route: GET /
resource "aws_apigatewayv2_route" "wake" {
  count     = var.enable_wake_api ? 1 : 0
  api_id    = aws_apigatewayv2_api.wake[0].id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.wake[0].id}"
}

# Allow API Gateway to invoke the Lambda
resource "aws_lambda_permission" "apigw_invoke" {
  count         = var.enable_wake_api ? 1 : 0
  statement_id  = "AllowInvokeByAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wake[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake[0].execution_arn}/*/*"
}

# Use $default stage with auto_deploy for simple URL like:
# https://{api_id}.execute-api.{region}.amazonaws.com
resource "aws_apigatewayv2_stage" "wake" {
  count       = var.enable_wake_api ? 1 : 0
  api_id      = aws_apigatewayv2_api.wake[0].id
  name        = "$default"
  auto_deploy = true
}

#############################################
# Auto-Sleep: EventBridge rule + Lambda
# Scales service back to 0 after N minutes idle
#############################################

# Role for the auto-sleep Lambda
resource "aws_iam_role" "autosleep_role" {
  count = var.enable_auto_sleep ? 1 : 0
  name  = "${var.project_name}-autosleep-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = var.project_name }
}

# Inline permissions for auto-sleep Lambda
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

# Auto-sleep Lambda (Python). Zip must exist: ./sleep.zip (contains auto_sleep.py)
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

# EventBridge: run every minute to check if service should sleep
resource "aws_cloudwatch_event_rule" "autosleep" {
  count               = var.enable_auto_sleep ? 1 : 0
  name                = "${var.project_name}-autosleep"
  schedule_expression = "rate(1 minute)"
}

# Connect rule -> Lambda target
resource "aws_cloudwatch_event_target" "autosleep" {
  count     = var.enable_auto_sleep ? 1 : 0
  rule      = aws_cloudwatch_event_rule.autosleep[0].name
  target_id = "autosleep-lambda"
  arn       = aws_lambda_function.autosleep[0].arn
}

# Allow EventBridge to invoke the auto-sleep Lambda
resource "aws_lambda_permission" "events_invoke_autosleep" {
  count         = var.enable_auto_sleep ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.autosleep[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.autosleep[0].arn
}

#############################################
# Outputs (useful in CI/CD & manual checks)
#############################################

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

# Open this URL to wake service and auto-redirect to task IP
output "wake_url" {
  value       = try(aws_apigatewayv2_api.wake[0].api_endpoint, null)
  description = "Public HTTP API URL to wake the ECS service."
}