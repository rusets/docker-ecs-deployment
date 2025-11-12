#############################################
# CloudWatch Logs for ECS tasks
#############################################

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 3 # short retention to save cost
  tags              = { Project = var.project_name }
}
