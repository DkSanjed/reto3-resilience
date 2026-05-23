data "archive_file" "orchestrator" {
  type        = "zip"
  source_file = "${path.module}/lambda/orchestrator/handler.py"
  output_path = "${path.module}/lambda/orchestrator/handler.zip"
}

data "archive_file" "level" {
  for_each    = local.level_lambdas
  type        = "zip"
  source_file = "${path.module}/lambda/${each.key}/handler.py"
  output_path = "${path.module}/lambda/${each.key}/handler.zip"
}

data "archive_file" "health" {
  type        = "zip"
  source_file = "${path.module}/lambda/health/handler.py"
  output_path = "${path.module}/lambda/health/handler.zip"
}

resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${var.project}-orchestrator"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "level" {
  for_each          = local.level_lambdas
  name              = "/aws/lambda/${var.project}-${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "health" {
  name              = "/aws/lambda/${var.project}-health"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "level" {
  for_each = local.level_lambdas

  function_name    = "${var.project}-${each.key}"
  description      = each.value.description
  role             = aws_iam_role.level.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.level[each.key].output_path
  source_code_hash = data.archive_file.level[each.key].output_base64sha256
  timeout          = 5
  memory_size      = 128

  depends_on = [aws_cloudwatch_log_group.level]
}

resource "aws_lambda_function" "orchestrator" {
  function_name    = "${var.project}-orchestrator"
  description      = "Orquestador: decide nivel y rutea a Lambda correspondiente"
  role             = aws_iam_role.orchestrator.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.orchestrator.output_path
  source_code_hash = data.archive_file.orchestrator.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      STATE_TABLE        = aws_dynamodb_table.service_state.name
      TRANSITIONS_TABLE  = aws_dynamodb_table.transitions_log.name
      LEVEL_1_FUNCTION   = aws_lambda_function.level["level-1"].function_name
      LEVEL_2_FUNCTION   = aws_lambda_function.level["level-2"].function_name
      LEVEL_3_FUNCTION   = aws_lambda_function.level["level-3"].function_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.orchestrator,
    aws_iam_role_policy.orchestrator,
  ]
}

resource "aws_lambda_function" "health" {
  function_name    = "${var.project}-health"
  description      = "Endpoint de salud — consulta estado sin modificarlo"
  role             = aws_iam_role.health.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.health.output_path
  source_code_hash = data.archive_file.health.output_base64sha256
  timeout          = 5
  memory_size      = 128

  environment {
    variables = {
      STATE_TABLE = aws_dynamodb_table.service_state.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.health]
}
