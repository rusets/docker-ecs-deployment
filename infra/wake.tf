
############################################
# IAM Role — execution role for Wake Lambda (ECS read/update + Logs)
############################################
resource "aws_iam_role" "wake_role" {
  count = var.enable_wake_api ? 1 : 0
  name  = "wake-ecs-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = { Project = var.project_name }
}

############################################
# IAM Inline Policy — permissions for ECS inspect/scale and logging
############################################
resource "aws_iam_role_policy" "wake_policy" {
  count = var.enable_wake_api ? 1 : 0
  name  = "wake-ecs-inline"
  role  = aws_iam_role.wake_role[0].id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:ListTasks", "ecs:DescribeTasks"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:DescribeNetworkInterfaces"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" }
    ]
  })
}

############################################
# Lambda Function — Wake handler (Python 3.12, proxy-integrated)
############################################
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

############################################
# API Gateway (HTTP API) — Wake endpoint API
############################################
resource "aws_apigatewayv2_api" "wake" {
  count         = var.enable_wake_api ? 1 : 0
  name          = "${var.project_name}-wake"
  protocol_type = "HTTP"
}

############################################
# API Integration — Lambda proxy (payload v2.0)
############################################
resource "aws_apigatewayv2_integration" "wake" {
  count                  = var.enable_wake_api ? 1 : 0
  api_id                 = aws_apigatewayv2_api.wake[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.wake[0].invoke_arn
  payload_format_version = "2.0"
}

############################################
# API Route — GET /
############################################
resource "aws_apigatewayv2_route" "wake" {
  count     = var.enable_wake_api ? 1 : 0
  api_id    = aws_apigatewayv2_api.wake[0].id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.wake[0].id}"
}

############################################
# Lambda Permission — allow API Gateway to invoke Wake Lambda
############################################
resource "aws_lambda_permission" "apigw_invoke" {
  count         = var.enable_wake_api ? 1 : 0
  statement_id  = "AllowInvokeByAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wake[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.wake[0].execution_arn}/*/*"
}

############################################
# API Stage — $default with auto-deploy for simple base URL
############################################
resource "aws_apigatewayv2_stage" "wake" {
  count       = var.enable_wake_api ? 1 : 0
  api_id      = aws_apigatewayv2_api.wake[0].id
  name        = "$default"
  auto_deploy = true
}
