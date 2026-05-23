variable "aws_region" {
  description = "Región AWS de despliegue"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo para todos los recursos"
  type        = string
  default     = "ultraseguros"
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch"
  type        = number
  default     = 7
}
