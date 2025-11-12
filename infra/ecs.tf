# infra/ecs.tf
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
    cpu_architecture        = "ARM64" # Graviton2/3 (cheaper)
  }

  tags = { Project = var.project_name }
}

# ECS service on Fargate with public IP (no ALB; connect directly to task ENI)
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count # 0 by default (idle)
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true # attach public IP to task ENI
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
