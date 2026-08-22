###############################################################################
# API Gateway - HTTP API
#
# HTTP API (no REST API): menor latencia y coste, y trae el JWT Authorizer
# nativo de Cognito, que evita una Lambda authorizer propia.
#
#   GET    /articles        -> publico
#   POST   /articles        -> JWT
#   PUT    /articles/{id}   -> JWT
#   DELETE /articles/{id}   -> JWT
###############################################################################

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name_prefix}-api"
  description   = "API REST de articulos de NewsNow"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_allow_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }

  tags = merge(local.common_tags, { Component = "api" })
}

###############################################################################
# Authorizer JWT contra el User Pool
###############################################################################

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "${local.name_prefix}-cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    # `endpoint` ya devuelve "cognito-idp.<region>.amazonaws.com/<pool-id>".
    issuer   = "https://${aws_cognito_user_pool.this.endpoint}"
    audience = [aws_cognito_user_pool_client.admin_app.id]
  }
}

###############################################################################
# Integraciones Lambda (proxy, payload 2.0)
###############################################################################

locals {
  routes = {
    get_articles = {
      route_key  = "GET /articles"
      invoke_arn = module.get_articles.invoke_arn
      name       = module.get_articles.function_name
      protected  = false
    }
    create_article = {
      route_key  = "POST /articles"
      invoke_arn = module.create_article.invoke_arn
      name       = module.create_article.function_name
      protected  = true
    }
    update_article = {
      route_key  = "PUT /articles/{id}"
      invoke_arn = module.update_article.invoke_arn
      name       = module.update_article.function_name
      protected  = true
    }
    delete_article = {
      route_key  = "DELETE /articles/{id}"
      invoke_arn = module.delete_article.invoke_arn
      name       = module.delete_article.function_name
      protected  = true
    }
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  for_each = local.routes

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = var.lambda_timeout * 1000
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.lambda[each.key].id}"

  authorization_type = each.value.protected ? "JWT" : "NONE"
  authorizer_id      = each.value.protected ? aws_apigatewayv2_authorizer.cognito.id : null
}

# Permiso de invocacion: acotado a esta API concreta.
resource "aws_lambda_permission" "apigw" {
  for_each = local.routes

  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = each.value.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

###############################################################################
# Stage $default con logs de acceso
###############################################################################

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${local.name_prefix}-api"
  retention_in_days = var.log_retention_days
  tags              = merge(local.common_tags, { Component = "api" })
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn

    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      path             = "$context.path"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
      authorizerError  = "$context.authorizer.error"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = var.api_throttling_burst_limit
    throttling_rate_limit    = var.api_throttling_rate_limit
  }

  tags = merge(local.common_tags, { Component = "api" })
}
