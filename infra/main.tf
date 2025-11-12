############################################
# Auto-Sleep — EventBridge rule + Lambda
# Purpose: scale ECS service to 0 after N minutes idle
############################################

############################################
# IAM Role — execution role for Auto-Sleep Lambda
# Allows Lambda to assume role and access ECS + Logs
############################################
resource "aws_iam_role" "autosleep_role" {
  count = var.enable_auto_sleep ? 1 : 0
  name  = "${var.project_name}-autosleep-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "lambda.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

############################################
# IAM Inline Policy — ECS and CloudWatch access
# Grants Lambda ability to read ECS status and scale services
############################################
resource "aws_iam_role_policy" "autosleep_policy" {
  count = var.enable_auto_sleep ? 1 : 0
  name  = "${var.project_name}-autosleep-inline"
  role  = aws_iam_role.autosleep_role[0].id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:DescribeServices",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:UpdateService"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

############################################
# Lambda Function — Auto-Sleep logic (Python)
# Checks ECS service every minute and scales down if idle
############################################
resource "aws_lambda_function" "autosleep" {
  count         = var.enable_auto_sleep ? 1 : 0
  function_name = "${var.project_name}-autosleep"
  role          = aws_iam_role.autosleep_role[0].arn
  runtime       = "python3.12"
  handler       = "auto_sleep.handler"

  filename         = local.sleep_zip_path
  source_code_hash = local.sleep_zip_hash
  timeout          = 15

  environment {
    variables = {
      CLUSTER_NAME        = aws_ecs_cluster.this.name
      SERVICE_NAME        = aws_ecs_service.app.name
      SLEEP_AFTER_MINUTES = tostring(var.sleep_after_minutes)
    }
  }

  depends_on = [
    aws_iam_role_policy.autosleep_policy
  ]
}

############################################
# EventBridge Rule — periodic trigger
# Executes Auto-Sleep Lambda every minute
############################################
resource "aws_cloudwatch_event_rule" "autosleep" {
  count               = var.enable_auto_sleep ? 1 : 0
  name                = "${var.project_name}-autosleep"
  schedule_expression = "rate(1 minute)"
}

############################################
# EventBridge Target — link to Lambda
# Connects scheduled rule to Auto-Sleep function
############################################
resource "aws_cloudwatch_event_target" "autosleep" {
  count     = var.enable_auto_sleep ? 1 : 0
  rule      = aws_cloudwatch_event_rule.autosleep[0].name
  target_id = "autosleep-lambda"
  arn       = aws_lambda_function.autosleep[0].arn
}

############################################
# Lambda Permission — EventBridge invocation
# Allows EventBridge rule to invoke the Auto-Sleep Lambda
############################################
resource "aws_lambda_permission" "events_invoke_autosleep" {
  count         = var.enable_auto_sleep ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.autosleep[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.autosleep[0].arn
}
