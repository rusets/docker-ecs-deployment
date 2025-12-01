#############################################
# CloudWatch Logs for ECS tasks
#############################################
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 3 # short retention to save cost
  tags              = { Project = var.project_name }
}


############################################
# CloudWatch Log Group — API Gateway wake
# Purpose: Store access logs for wake HTTP API
############################################
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "apigw_wake" {
  name              = "/apigw/${var.project_name}-wake"
  retention_in_days = 7

  tags = {
    Project = var.project_name
  }
}


