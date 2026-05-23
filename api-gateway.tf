# ════════════════════════════════════════════════════════════
#   API Gateway REST
#   Endpoints:
#     POST /service-api  →  orchestrator
#     GET  /health       →  health
# ════════════════════════════════════════════════════════════
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project}-api"
  description = "API Gateway para Sistemas UltraSeguros - Reto 3"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ──────────────────────────────────────────────────────────
#   Recurso: /service-api (POST)
# ──────────────────────────────────────────────────────────
resource "aws_api_gateway_resource" "service_api" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "service-api"
}

resource "aws_api_gateway_method" "service_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.service_api.id
  http_method   = "POST"
  authorization = "NONE"
  # NOTA: api_key_required = false porque el script K6 no envía API key.
  # En producción debería ser true + un Usage Plan con quotas.
}

resource "aws_api_gateway_integration" "service_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.service_api.id
  http_method             = aws_api_gateway_method.service_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.orchestrator.invoke_arn
}

# ──────────────────────────────────────────────────────────
#   Recurso: /health (GET)
# ──────────────────────────────────────────────────────────
resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "health"
}

resource "aws_api_gateway_method" "health_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "health_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.health_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.health.invoke_arn
}

# ──────────────────────────────────────────────────────────
#   Deployment + Stage
# ──────────────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  # Re-deploy automático si cambia algo
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.service_api.id,
      aws_api_gateway_method.service_post.id,
      aws_api_gateway_integration.service_lambda.id,
      aws_api_gateway_resource.health.id,
      aws_api_gateway_method.health_get.id,
      aws_api_gateway_integration.health_lambda.id,
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.service_lambda,
    aws_api_gateway_integration.health_lambda,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
}

# ──────────────────────────────────────────────────────────
#   Throttling a nivel de método (rate limiting)
#   Protección básica sin requerir API key
# ──────────────────────────────────────────────────────────
resource "aws_api_gateway_method_settings" "service_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "${aws_api_gateway_resource.service_api.path_part}/${aws_api_gateway_method.service_post.http_method}"

  settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
    metrics_enabled        = true
  }
}

# ──────────────────────────────────────────────────────────
#   Permisos para que API Gateway invoque las Lambdas
# ──────────────────────────────────────────────────────────
resource "aws_lambda_permission" "apigw_orchestrator" {
  statement_id  = "AllowAPIGatewayInvokeOrchestrator"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_health" {
  statement_id  = "AllowAPIGatewayInvokeHealth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
