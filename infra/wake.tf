
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
# IAM Policy — Wake Lambda permissions
# Purpose: Scale ECS service and inspect running tasks
############################################
resource "aws_iam_role_policy" "wake_policy" {
  name = "${var.project_name}-wake-policy"
  role = aws_iam_role.wake_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageEcsServiceFromWake"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}"
      },
      {
        Sid    = "InspectTasksForPublicIp"
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      },
      {
        Sid    = "WriteWakeLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-wake",
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-wake:*"
        ]
      }
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

  filename         = data.archive_file.wake_zip.output_path
  source_code_hash = data.archive_file.wake_zip.output_base64sha256

  timeout = 29

  environment {
    variables = {
      CLUSTER_NAME = aws_ecs_cluster.this.name
      SERVICE_NAME = aws_ecs_service.app.name
      APP_PORT     = tostring(var.app_port)
      WAIT_MS      = "120000"
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_iam_role_policy.wake_policy]
}

############################################
# API Gateway (HTTP API) — Wake endpoint API (OpenAPI-driven)
# Purpose: Define routes and Lambda integration via OpenAPI spec
############################################
resource "aws_apigatewayv2_api" "wake" {
  count         = var.enable_wake_api ? 1 : 0
  name          = "${var.project_name}-wake"
  protocol_type = "HTTP"

  body = templatefile("${path.module}/api/openapi-wake.yaml", {
    wake_lambda_invoke_arn = "arn:aws:apigateway:${data.aws_region.current.id}:lambda:path/2015-03-31/functions/${aws_lambda_function.wake[0].arn}/invocations"
  })
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
# API Gateway Stage — wake default
# Purpose: Enable access logging for wake API
############################################
resource "aws_apigatewayv2_stage" "wake" {
  count       = var.enable_wake_api ? 1 : 0
  api_id      = aws_apigatewayv2_api.wake[0].id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_wake.arn
    format = jsonencode({
      requestId   = "$context.requestId"
      httpMethod  = "$context.httpMethod"
      path        = "$context.path"
      status      = "$context.status"
      ip          = "$context.identity.sourceIp"
      userAgent   = "$context.identity.userAgent"
      requestTime = "$context.requestTime"
    })
  }
}
