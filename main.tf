terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "Reto3-UltraSeguros"
      ManagedBy = "Terraform"
    }
  }
}

locals {
  # Lambdas de nivel — se generan de forma uniforme con for_each
  level_lambdas = {
    "level-1" = { description = "Servicio Nivel 1 - Full" }
    "level-2" = { description = "Servicio Nivel 2 - Degradado" }
    "level-3" = { description = "Servicio Nivel 3 - Operación Mínima" }
  }
}
