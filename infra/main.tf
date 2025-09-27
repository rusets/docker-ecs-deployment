// infra/main.tf
// Minimal-cost ECS Fargate (no ALB). Public IP on the task. ARM64 (Graviton).

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket         = "docker-ecs-deployment"
    key            = "ecs-demo/infra.tfstate"   # было ecs-no-alb/...
    region         = "us-east-1"
    dynamodb_table = "docker-ecs-deployment"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

########################
# Variables
########################
variable "project_name" {
  type        = string
  default     = "ecs-demo"   # было ecs-no-alb-demo
  description = "Project name prefix"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnets" {
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "desired_count" {
  type        = number
  default     = 0   // 0 by default to pay $0 when idle
  description = "Number of desired tasks (0 = fully idle)"
}

variable "task_cpu" {
  type        = string
  default     = "256" // 0.25 vCPU
}

variable "task_memory" {
  type        = string
  default     = "512" // 0.5 GB
}

variable "app_port" {
  type        = number
  default     = 80
  description = "Container port exposed by Node app"
}

variable "ecr_repo_name" {
  type        = string
  default     = "ecs-demo-app"   # было ecs-no-alb-app
}

########################
# VPC (public subnets only)
########################
data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.2.0"

  name = var.project_name
  cidr = var.vpc_cidr

  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = var.public_subnets

  enable_nat_gateway  = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

########################
# Security Group (world -> app_port)
########################
resource "aws_security_group" "service" {
  name_prefix = "${var.project_name}-svc-"
  description = "Allow HTTP to app"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description      = "HTTP from anywhere"
    from_port        = var.app_port
    to_port          = var.app_port
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Project = var.project_name }
}

########################
# ECR (with lifecycle policy)
########################
resource "aws_ecr_repository" "this" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }

  tags = { Project = var.project_name }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Expire untagged after 7 days",
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 },
        action       = { type = "expire" }
      },
      {
        rulePriority = 2,
        description  = "Keep last 10 latest",
        selection    = { tagStatus = "tagged", tagPrefixList = ["latest"], countType = "imageCountMoreThan", countNumber = 10 },
        action       = { type = "expire" }
      }
    ]
  })
}

########################
# CloudWatch Logs (short retention)
########################
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 3
  tags              = { Project = var.project_name }
}

########################
# ECS: Cluster, Roles, Task, Service
########################
resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"  // ecs-demo-cluster
}

# Execution role (pull from ECR, write logs)
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

# Task role (app permissions; empty by default)
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = aws_iam_role.ecs_execution_role.assume_role_policy
  tags               = { Project = var.project_name }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"  // ecs-demo-task
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
      },
      environment = [
        { name = "APP_NAME", value = "Ruslan AWS 🚀" },
        { name = "APP_ENV",  value = "prod" }
      ]
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"   // оставляем Graviton для экономии
  }

  tags = { Project = var.project_name }
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-svc"   // ecs-demo-svc
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

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Project = var.project_name }
}

########################
# Outputs
########################
output "ecr_repository_url" {
  value       = aws_ecr_repository.this.repository_url
  description = "ECR repo URL (push your image here)"
}

output "cluster_name" { value = aws_ecs_cluster.this.name }   # ecs-demo-cluster
output "service_name" { value = aws_ecs_service.app.name }    # ecs-demo-svc
output "region"       { value = var.region }