############################################
# API Mapping — ecs-demo.online → wake HTTP API
# Purpose: Attach $default stage to root domain
############################################
resource "aws_apigatewayv2_api_mapping" "ecs_demo_root" {
  api_id      = aws_apigatewayv2_api.wake[0].id
  domain_name = "ecs-demo.online"
  stage       = aws_apigatewayv2_stage.wake[0].id
}

############################################
# API Mapping — api.ecs-demo.online → wake HTTP API
# Purpose: Attach $default stage to api subdomain
############################################
resource "aws_apigatewayv2_api_mapping" "ecs_demo_api" {
  api_id      = aws_apigatewayv2_api.wake[0].id
  domain_name = "api.ecs-demo.online"
  stage       = aws_apigatewayv2_stage.wake[0].id
}
