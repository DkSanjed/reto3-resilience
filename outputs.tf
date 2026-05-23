output "api_service_url" {
  description = "URL del endpoint principal — pega esto en el script K6"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/service-api"
}

output "api_health_url" {
  description = "URL del endpoint de salud — consulta sin afectar contadores"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/health"
}

output "dashboard_url" {
  description = "URL del Dashboard de CloudWatch"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "state_table" {
  description = "Tabla DynamoDB con el estado actual"
  value       = aws_dynamodb_table.service_state.name
}

output "transitions_table" {
  description = "Tabla DynamoDB con el historial de transiciones"
  value       = aws_dynamodb_table.transitions_log.name
}

output "reset_state_command" {
  description = "Comando para resetear el estado entre pruebas (PowerShell)"
  value       = <<-EOT
    aws dynamodb put-item --table-name ${aws_dynamodb_table.service_state.name} --item '{\"id\":{\"S\":\"state\"},\"level\":{\"N\":\"1\"},\"error_count\":{\"N\":\"0\"},\"success_streak\":{\"N\":\"0\"}}' --region ${var.aws_region}
  EOT
}

output "tail_logs_command" {
  description = "Comando para ver logs de la orquestadora en vivo"
  value       = "aws logs tail /aws/lambda/${var.project}-orchestrator --follow --region ${var.aws_region}"
}
