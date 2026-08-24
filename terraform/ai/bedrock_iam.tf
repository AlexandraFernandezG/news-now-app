###############################################################################
# IAM - permisos de las Lambdas de IA
#
# Mismo criterio que el stack de Fase 1 (terraform/iam.tf): cada funcion
# recibe unicamente las acciones que ejecuta, via el modulo lambda-function
# (que crea el rol y aplica estos statements como politica inline). Nada de
# dynamodb:* ni de politicas gestionadas amplias.
#
#   summarize_article -> InvokeModel (solo Haiku) + UpdateItem en `articles`
#                         + lectura del stream (la exige el propio event
#                         source mapping, no el codigo Python) + SendMessage
#                         a su propia DLQ
#   daily_digest       -> InvokeModel (solo Sonnet) + Query en `articles`
#                         (GSI publish_date-index) + PutItem en `digests`
#
# bedrock:InvokeModel se acota al ARN del modelo concreto que usa cada
# Lambda: Haiku y Sonnet nunca comparten permiso de invocacion.
###############################################################################

locals {
  # Estos modelos Claude solo se invocan via inference profile (no hay
  # ARN "foundation-model" bajo demanda para estos modelos). El permiso tiene
  # que cubrir dos ARN, patron documentado por AWS para inferencia
  # cross-region:
  #   1. el inference profile en si (regional, con cuenta)
  #   2. los modelos fundacionales a los que ese profile puede enrutar la
  #      invocacion en tiempo de ejecucion (comodin de region: el profile
  #      decide en cual invoca, no nosotros) -- de ahi el "*" en vez de
  #      var.aws_region.
  haiku_profile_arn  = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.haiku_model_id}"
  sonnet_profile_arn = "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.sonnet_model_id}"

  # El id del profile lleva el prefijo de enrutado ("eu.", "global.", ...)
  # que el modelo fundacional subyacente no tiene.
  haiku_foundation_model_arn  = "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/${replace(var.haiku_model_id, "/^(eu|us|apac|global)\\./", "")}"
  sonnet_foundation_model_arn = "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/${replace(var.sonnet_model_id, "/^(eu|us|apac|global)\\./", "")}"

  policy_summarize_article = [
    {
      sid       = "InvokeHaiku"
      effect    = "Allow"
      actions   = ["bedrock:InvokeModel"]
      resources = [local.haiku_profile_arn, local.haiku_foundation_model_arn]
    },
    {
      sid       = "UpdateArticleSummary"
      effect    = "Allow"
      actions   = ["dynamodb:UpdateItem"]
      resources = [data.aws_dynamodb_table.articles.arn]
    },
    {
      # Sin esto el event source mapping no puede leer el stream: lo exige
      # el poller de Lambda, no una llamada que haga el handler.
      sid    = "ReadArticlesStream"
      effect = "Allow"
      actions = [
        "dynamodb:DescribeStream",
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
      ]
      resources = [data.aws_dynamodb_table.articles.stream_arn]
    },
    {
      # ListStreams no admite acotarse a un stream ni a una tabla concreta:
      # el propio catalogo de acciones de IAM de DynamoDB solo permite "*"
      # como resource para esta accion.
      sid       = "ListDynamodbStreams"
      effect    = "Allow"
      actions   = ["dynamodb:ListStreams"]
      resources = ["*"]
    },
    {
      sid       = "SendToOwnDlq"
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.summarize_article_dlq.arn]
    },
  ]

  policy_daily_digest = [
    {
      sid       = "InvokeSonnet"
      effect    = "Allow"
      actions   = ["bedrock:InvokeModel"]
      resources = [local.sonnet_profile_arn, local.sonnet_foundation_model_arn]
    },
    {
      # Solo la GSI, no la tabla base: el digest nunca lee por id.
      sid       = "QueryArticlesByPublishDate"
      effect    = "Allow"
      actions   = ["dynamodb:Query"]
      resources = ["${data.aws_dynamodb_table.articles.arn}/index/*"]
    },
    {
      sid       = "WriteDigest"
      effect    = "Allow"
      actions   = ["dynamodb:PutItem"]
      resources = [aws_dynamodb_table.digests.arn]
    },
  ]
}
