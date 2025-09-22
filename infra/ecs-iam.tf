# Execution role: lets ECS pull ECR images and write logs
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: app permissions (empty by default). Add SSM or other permissions here if needed later.
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = aws_iam_role.ecs_execution_role.assume_role_policy
  tags               = { Project = var.project_name }
}
