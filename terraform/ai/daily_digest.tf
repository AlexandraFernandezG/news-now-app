###############################################################################
# Lambda daily_digest
#
# Sin trigger de eventos: EventBridge Scheduler la invoca directamente una
# vez al dia. A diferencia de una regla de EventBridge clasica
# (aws_cloudwatch_event_rule), el Scheduler no necesita un
# aws_lambda_permission -- invoca a traves del rol IAM que se le asigna en
# `target.role_arn`, no de la resource policy de la funcion.
###############################################################################

module "daily_digest" {
  source = "../modules/lambda-function"

  function_name = "${local.name_prefix}-daily-digest"
  description   = "Genera el digest diario de articulos con Bedrock (Claude Sonnet, ver sonnet_model_id)"
  handler       = "daily_digest.lambda_handler"
  runtime       = var.lambda_runtime
  source_files = {
    "daily_digest.py" = "${local.ai_source_dir}/daily_digest.py"
  }

  memory_size        = var.daily_digest_memory_size
  timeout            = var.daily_digest_timeout
  log_retention_days = var.log_retention_days

  environment_variables = {
    ARTICLES_TABLE_NAME = var.articles_table_name
    PUBLISH_DATE_INDEX  = var.articles_publish_date_index
    DIGESTS_TABLE_NAME  = aws_dynamodb_table.digests.name
    SONNET_MODEL_ID     = var.sonnet_model_id
    LOG_LEVEL           = var.log_level
  }

  policy_statements = local.policy_daily_digest

  tags = merge(local.common_tags, { Component = "ai", Function = "daily-digest" })
}

###############################################################################
# Rol que asume EventBridge Scheduler para invocar daily_digest
###############################################################################

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "daily_digest_scheduler" {
  name               = "${local.name_prefix}-daily-digest-scheduler-role"
  description        = "Rol que usa EventBridge Scheduler para invocar daily_digest"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "scheduler_invoke_daily_digest" {
  statement {
    sid       = "InvokeDailyDigest"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [module.daily_digest.function_arn]
  }
}

resource "aws_iam_role_policy" "daily_digest_scheduler" {
  name   = "invoke-daily-digest"
  role   = aws_iam_role.daily_digest_scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke_daily_digest.json
}

###############################################################################
# EventBridge Scheduler - cron diario, ejecucion exacta sin ventana
###############################################################################

resource "aws_scheduler_schedule" "daily_digest" {
  name       = "${local.name_prefix}-daily-digest"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = var.daily_digest_schedule_expression
  schedule_expression_timezone = "UTC"

  target {
    arn      = module.daily_digest.function_arn
    role_arn = aws_iam_role.daily_digest_scheduler.arn
  }
}
