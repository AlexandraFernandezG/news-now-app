###############################################################################
# NewsNow - Fase 2: capa de IA
#
#   Stream `articles` -> summarize_article (Bedrock Haiku) -> UpdateItem
#                                                              (summary, summary_status)
#
#   EventBridge Scheduler (cron 07:00 UTC) -> daily_digest (Bedrock Sonnet)
#       -> Query GSI publish_date-index -> PutItem en DynamoDB `digests`
#
# Stack independiente del de Fase 1 (estado propio, ver backend.tf): añade la
# generacion de resumenes sobre la infraestructura ya desplegada sin tocarla.
# La tabla `articles` se referencia por nombre (data source) en lugar de
# gestionarse aqui, precisamente para no acoplar los dos estados.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 7.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# Tabla creada por el stack de Fase 1 (terraform/dynamodb.tf): se referencia
# por nombre, nunca se declara aqui.
data "aws_dynamodb_table" "articles" {
  name = var.articles_table_name
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "ai-layer"
    },
    var.tags
  )

  # Cada handler de ai-summarizer/ se empaqueta suelto (sin "common/"): una
  # Lambda, un fichero.
  ai_source_dir = "${path.module}/../../ai-summarizer"
}
