###############################################################################
# IAM - permisos de las Lambdas
#
# Cada funcion recibe SU rol (lo crea el modulo lambda-function) con una
# politica inline que contiene unicamente las acciones DynamoDB que ejecuta
# su handler. Nada de dynamodb:* ni de politicas gestionadas amplias.
#
#   get_articles    -> Query (GSI) + Scan + GetItem   [solo lectura]
#   create_article  -> PutItem
#   update_article  -> UpdateItem
#   delete_article  -> DeleteItem
#
# Los permisos de escritura de logs y de X-Ray los anade el propio modulo,
# acotados al log group de cada funcion.
###############################################################################

locals {
  articles_table_arn = aws_dynamodb_table.articles.arn

  # Los indices son un recurso distinto de la tabla en IAM.
  articles_index_arns = ["${aws_dynamodb_table.articles.arn}/index/*"]

  policy_get_articles = [
    {
      sid    = "ReadArticles"
      effect = "Allow"
      actions = [
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan",
      ]
      resources = concat([local.articles_table_arn], local.articles_index_arns)
    },
  ]

  policy_create_article = [
    {
      sid       = "CreateArticle"
      effect    = "Allow"
      actions   = ["dynamodb:PutItem"]
      resources = [local.articles_table_arn]
    },
  ]

  policy_update_article = [
    {
      # UpdateItem con ConditionExpression attribute_exists(id): no hace falta
      # GetItem previo, la propia escritura condicional valida la existencia.
      sid       = "UpdateArticle"
      effect    = "Allow"
      actions   = ["dynamodb:UpdateItem"]
      resources = [local.articles_table_arn]
    },
  ]

  policy_delete_article = [
    {
      sid       = "DeleteArticle"
      effect    = "Allow"
      actions   = ["dynamodb:DeleteItem"]
      resources = [local.articles_table_arn]
    },
  ]
}
