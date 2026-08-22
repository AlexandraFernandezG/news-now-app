###############################################################################
# Modulo: lambda-function
#
# Empaqueta y despliega una Lambda en Python junto con las dos piezas que
# siempre la acompanan y que no queremos duplicar cuatro veces:
#   - un rol de ejecucion EXCLUSIVO de esa funcion, con permisos minimos
#   - su CloudWatch Log Group, creado explicitamente y con retencion acotada
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

locals {
  log_group_name = "/aws/lambda/${var.function_name}"
  package_path   = "${path.module}/.build/${var.function_name}.zip"
}

###############################################################################
# Empaquetado del codigo
###############################################################################

data "archive_file" "package" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = local.package_path
  excludes    = var.source_excludes
}

###############################################################################
# Rol de ejecucion (uno por funcion)
###############################################################################

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.function_name}-role"
  description        = "Rol de ejecucion de la Lambda ${var.function_name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

# Logging: se conceden solo los permisos de escritura sobre SU log group.
# No se usa la politica gestionada AWSLambdaBasicExecutionRole porque concede
# logs:* sobre "*", y el log group ya lo crea Terraform mas abajo.
data "aws_iam_policy_document" "logging" {
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.this.arn}:*",
    ]
  }

  dynamic "statement" {
    for_each = var.tracing_mode == "Active" ? [1] : []

    content {
      sid    = "XRayTracing"
      effect = "Allow"
      actions = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "logging" {
  name   = "logging"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.logging.json
}

# Permisos funcionales especificos de esta Lambda (acceso a DynamoDB, etc.).
data "aws_iam_policy_document" "custom" {
  count = length(var.policy_statements) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = var.policy_statements

    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "custom" {
  count = length(var.policy_statements) > 0 ? 1 : 0

  name   = "function-permissions"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.custom[0].json
}

###############################################################################
# Log group
###############################################################################

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

###############################################################################
# Funcion
###############################################################################

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  description   = var.description
  role          = aws_iam_role.this.arn
  handler       = var.handler
  runtime       = var.runtime
  architectures = ["arm64"]

  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256

  memory_size = var.memory_size
  timeout     = var.timeout

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []

    content {
      variables = var.environment_variables
    }
  }

  tracing_config {
    mode = var.tracing_mode
  }

  tags = var.tags

  # El log group debe existir antes que la funcion para que la retencion de
  # 14 dias se aplique desde la primera invocacion.
  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.logging,
  ]
}
