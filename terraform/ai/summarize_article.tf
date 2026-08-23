###############################################################################
# Lambda summarize_article
#
# Consumidor del stream de la tabla `articles` (Fase 1). El event source
# mapping filtra por eventName para no invocar la funcion en los DELETE
# (REMOVE): summarize_article no tiene nada que hacer con un articulo
# borrado. El filtro por summary_status = PENDING vive en el propio handler
# (ai-summarizer/summarize_article.py), no aqui: los streams no permiten
# filtrar por ese valor sin exponer la logica de negocio en HCL.
###############################################################################

module "summarize_article" {
  source = "../modules/lambda-function"

  function_name = "${local.name_prefix}-summarize-article"
  description   = "Genera el resumen de un articulo con Bedrock (Claude Haiku 4.5)"
  handler       = "summarize_article.lambda_handler"
  runtime       = var.lambda_runtime
  source_files = {
    "summarize_article.py" = "${local.ai_source_dir}/summarize_article.py"
  }

  memory_size        = var.summarize_article_memory_size
  timeout            = var.summarize_article_timeout
  log_retention_days = var.log_retention_days

  environment_variables = {
    ARTICLES_TABLE_NAME = var.articles_table_name
    HAIKU_MODEL_ID      = var.haiku_model_id
    LOG_LEVEL           = var.log_level
  }

  policy_statements = local.policy_summarize_article

  tags = merge(local.common_tags, { Component = "ai", Function = "summarize-article" })
}

###############################################################################
# Dead-letter queue
#
# Recoge los batches del stream que agotan los reintentos del event source
# mapping (p.ej. throttling sostenido de Bedrock): el articulo queda sin
# resumen (summary_status = ERROR, lo escribe el propio handler) pero el
# evento no se pierde, queda visible en la cola para investigar y reprocesar.
###############################################################################

resource "aws_sqs_queue" "summarize_article_dlq" {
  name = "${local.name_prefix}-summarize-article-dlq"

  # 14 dias (el maximo de SQS): margen de sobra para investigar antes de
  # perder el mensaje.
  message_retention_seconds = 1209600

  tags = merge(local.common_tags, { Component = "ai", Function = "summarize-article" })
}

###############################################################################
# Event source mapping - conecta el stream de `articles` con la Lambda
###############################################################################

resource "aws_lambda_event_source_mapping" "summarize_article" {
  event_source_arn = data.aws_dynamodb_table.articles.stream_arn
  function_name    = module.summarize_article.function_name

  # Solo eventos nuevos: no reprocesar la historia del stream (hasta 24h de
  # retencion) en cada despliegue.
  starting_position = "LATEST"
  batch_size        = 10

  # Reintentos finitos: sin este limite el event source mapping reintenta
  # indefinidamente (hasta que el registro expira del stream) y la DLQ nunca
  # llega a usarse.
  maximum_retry_attempts = 3

  # Evita invocar la Lambda para los DELETE (REMOVE), que no le corresponden.
  filter_criteria {
    filter {
      pattern = jsonencode({ eventName = ["INSERT", "MODIFY"] })
    }
  }

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.summarize_article_dlq.arn
    }
  }
}
