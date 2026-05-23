# ════════════════════════════════════════════════════════════
#   DynamoDB — Estado actual del sistema
# ════════════════════════════════════════════════════════════
resource "aws_dynamodb_table" "service_state" {
  name         = "${var.project}-service-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # Encriptación en reposo explícita (buena práctica)
  server_side_encryption {
    enabled = true
  }
}

# Ítem inicial: arranca en Nivel 1 con contadores en cero
resource "aws_dynamodb_table_item" "initial_state" {
  table_name = aws_dynamodb_table.service_state.name
  hash_key   = aws_dynamodb_table.service_state.hash_key

  item = jsonencode({
    id             = { S = "state" }
    level          = { N = "1" }
    error_count    = { N = "0" }
    success_streak = { N = "0" }
  })

  # Terraform NO sobreescribe el estado entre applies
  lifecycle {
    ignore_changes = [item]
  }
}

# ════════════════════════════════════════════════════════════
#   DynamoDB — Historial de transiciones (auditoría)
# ════════════════════════════════════════════════════════════
resource "aws_dynamodb_table" "transitions_log" {
  name         = "${var.project}-transitions-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "timestamp"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}
