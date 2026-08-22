###############################################################################
# Frontends
###############################################################################

output "public_app_url" {
  description = "URL publica del periodico (app de lectura)."
  value       = module.public_app.url
}

output "public_app_bucket" {
  description = "Bucket destino del build de la app publica."
  value       = module.public_app.bucket_name
}

output "public_app_distribution_id" {
  description = "Distribucion CloudFront de la app publica (para invalidaciones en el deploy)."
  value       = module.public_app.distribution_id
}

output "admin_app_url" {
  description = "URL del panel de administracion."
  value       = module.admin_app.url
}

output "admin_app_bucket" {
  description = "Bucket destino del build de la app de administracion."
  value       = module.admin_app.bucket_name
}

output "admin_app_distribution_id" {
  description = "Distribucion CloudFront de la app de administracion."
  value       = module.admin_app.distribution_id
}

###############################################################################
# API
###############################################################################

output "api_endpoint" {
  description = "Endpoint directo del HTTP API (sin cache). Util para depurar."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "api_url" {
  description = "URL de la API que deben consumir los frontends (a traves de CloudFront)."
  value       = "https://${aws_cloudfront_distribution.api.domain_name}"
}

output "api_distribution_id" {
  description = "Distribucion CloudFront que cachea GET /articles."
  value       = aws_cloudfront_distribution.api.id
}

output "api_cache_ttl_seconds" {
  description = "TTL efectivo de la cache del listado de articulos."
  value       = var.api_cache_ttl_seconds
}

###############################################################################
# Autenticacion
###############################################################################

output "cognito_user_pool_id" {
  description = "ID del User Pool de Cognito."
  value       = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  description = "ID del App Client usado por la SPA de administracion."
  value       = aws_cognito_user_pool_client.admin_app.id
}

output "cognito_hosted_ui_domain" {
  description = "Dominio del Hosted UI de Cognito."
  value       = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "cognito_issuer_url" {
  description = "Issuer que valida el authorizer JWT del HTTP API."
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

###############################################################################
# Datos y seguridad
###############################################################################

output "articles_table_name" {
  description = "Nombre de la tabla DynamoDB de articulos."
  value       = aws_dynamodb_table.articles.name
}

output "articles_table_stream_arn" {
  description = "ARN del stream de la tabla. Punto de enganche de la capa de IA (Fase 2)."
  value       = aws_dynamodb_table.articles.stream_arn
}

output "articles_publish_date_index" {
  description = "Nombre del GSI por fecha de publicacion (resumen diario, Fase 2)."
  value       = local.publish_date_index_name
}

output "waf_web_acl_arn" {
  description = "ARN del Web ACL asociado a la app publica."
  value       = aws_wafv2_web_acl.public_app.arn
}

output "lambda_function_names" {
  description = "Nombres de las cuatro funciones del CRUD."
  value = {
    get_articles   = module.get_articles.function_name
    create_article = module.create_article.function_name
    update_article = module.update_article.function_name
    delete_article = module.delete_article.function_name
  }
}
