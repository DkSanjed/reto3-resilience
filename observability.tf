# ════════════════════════════════════════════════════════════
#   CloudWatch Dashboard
#   Free Tier: 3 dashboards gratis. Usamos 1.
# ════════════════════════════════════════════════════════════
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-resilience"

  dashboard_body = jsonencode({
    widgets = [
      # ── Nivel actual del servicio ────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["UltraSeguros/Resilience", "CurrentLevel"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Maximum"
          period  = 60
          title   = "Nivel actual del servicio (1=Full, 2=Degradado, 3=Mínimo)"
          yAxis = {
            left = { min = 0, max = 3.5 }
          }
        }
      },
      # ── Contador de errores y racha de éxitos ────────────
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["UltraSeguros/Resilience", "ErrorCount"],
            [".", "SuccessStreak"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Maximum"
          period  = 60
          title   = "Contadores: errores acumulados y racha de éxitos"
        }
      },
      # ── Peticiones con error por minuto ──────────────────
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["UltraSeguros/Resilience", "ErrorRequests"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Sum"
          period  = 60
          title   = "Peticiones con error por minuto"
        }
      },
      # ── Transiciones de nivel ────────────────────────────
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["UltraSeguros/Resilience", "LevelTransition"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Sum"
          period  = 60
          title   = "Transiciones de nivel (cambios de estado)"
        }
      },
      # ── Invocaciones por Lambda ──────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project}-orchestrator"],
            ["...", "${var.project}-level-1"],
            ["...", "${var.project}-level-2"],
            ["...", "${var.project}-level-3"],
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          stat    = "Sum"
          period  = 60
          title   = "Invocaciones por Lambda"
        }
      },
    ]
  })
}

# ════════════════════════════════════════════════════════════
#   CloudWatch Alarms
#   Free Tier: 10 alarms gratis. Usamos 3.
# ════════════════════════════════════════════════════════════

# 1. Alarma: el sistema entró a Nivel 3 (mantenimiento)
resource "aws_cloudwatch_metric_alarm" "level_3_entered" {
  alarm_name          = "${var.project}-system-in-maintenance"
  alarm_description   = "CRÍTICA: El sistema está en Nivel 3 (modo mantenimiento)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "CurrentLevel"
  namespace           = "UltraSeguros/Resilience"
  period              = 60
  statistic           = "Maximum"
  threshold           = 3
  treat_missing_data  = "notBreaching"
}

# 2. Alarma: tasa alta de errores
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${var.project}-high-error-rate"
  alarm_description   = "ADVERTENCIA: Más de 10 errores en el último minuto"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorRequests"
  namespace           = "UltraSeguros/Resilience"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
}

# 3. Alarma: errores en la Lambda orquestadora
resource "aws_cloudwatch_metric_alarm" "orchestrator_errors" {
  alarm_name          = "${var.project}-orchestrator-errors"
  alarm_description   = "ADVERTENCIA: Errores de runtime en la Lambda orquestadora"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.orchestrator.function_name
  }
}
