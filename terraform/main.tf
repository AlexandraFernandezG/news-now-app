###############################################################################
# NewsNow - Fase 1: infraestructura base
#
#   Lectores  -> CloudFront (+WAF) -> S3 news-now-public-app    (SPA publica)
#   Redaccion -> CloudFront        -> S3 news-now-admin-app     (SPA admin)
#   Ambas     -> CloudFront (cache GET /articles)
#                  -> API Gateway HTTP API (JWT authorizer Cognito)
#                     -> 4 Lambdas Python -> DynamoDB `articles` (+ Streams)
#
# Todo serverless/PaaS: escala solo ante los picos impredecibles de trafico.
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

# WAF con scope CLOUDFRONT solo puede crearse en us-east-1, aunque el resto
# del stack viva en var.aws_region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  # Todas las Lambdas comparten el mismo paquete (src/) para poder importar
  # src/common; cada una expone un handler distinto.
  lambda_source_dir = "${path.module}/../src"

  lambda_environment = {
    ARTICLES_TABLE_NAME = aws_dynamodb_table.articles.name
    PUBLISH_DATE_INDEX  = local.publish_date_index_name
    LOG_LEVEL           = var.log_level
    POWERTOOLS_ENV      = var.environment
  }
}

###############################################################################
# Frontends estaticos (modulo static-site)
###############################################################################

module "public_app" {
  source = "./modules/static-site"

  bucket_name = var.public_app_bucket_name
  comment     = "${local.name_prefix} - app publica de lectura"
  price_class = var.cloudfront_price_class

  # Unica distribucion con WAF en esta fase: es la expuesta al trafico masivo.
  web_acl_arn = aws_wafv2_web_acl.public_app.arn

  tags = merge(local.common_tags, { Component = "public-app" })
}

module "admin_app" {
  source = "./modules/static-site"

  bucket_name = var.admin_app_bucket_name
  comment     = "${local.name_prefix} - app de administracion"
  price_class = var.cloudfront_price_class

  # Sin WAF en Fase 1: el acceso real esta protegido por Cognito en la API.
  web_acl_arn = null

  tags = merge(local.common_tags, { Component = "admin-app" })
}

###############################################################################
# Lambdas del CRUD (modulo lambda-function)
#
# Un rol por funcion; las politicas concretas se definen en iam.tf.
###############################################################################

module "get_articles" {
  source = "./modules/lambda-function"

  function_name = "${local.name_prefix}-get-articles"
  description   = "GET /articles - listado publico de articulos"
  handler       = "articles.get_articles.lambda_handler"
  runtime       = var.lambda_runtime
  source_dir    = local.lambda_source_dir

  memory_size           = var.lambda_memory_size
  timeout               = var.lambda_timeout
  log_retention_days    = var.log_retention_days
  environment_variables = local.lambda_environment
  policy_statements     = local.policy_get_articles

  tags = merge(local.common_tags, { Component = "api", Route = "GET /articles" })
}

module "create_article" {
  source = "./modules/lambda-function"

  function_name = "${local.name_prefix}-create-article"
  description   = "POST /articles - alta de articulo (requiere JWT)"
  handler       = "articles.create_article.lambda_handler"
  runtime       = var.lambda_runtime
  source_dir    = local.lambda_source_dir

  memory_size           = var.lambda_memory_size
  timeout               = var.lambda_timeout
  log_retention_days    = var.log_retention_days
  environment_variables = local.lambda_environment
  policy_statements     = local.policy_create_article

  tags = merge(local.common_tags, { Component = "api", Route = "POST /articles" })
}

module "update_article" {
  source = "./modules/lambda-function"

  function_name = "${local.name_prefix}-update-article"
  description   = "PUT /articles/{id} - edicion de articulo (requiere JWT)"
  handler       = "articles.update_article.lambda_handler"
  runtime       = var.lambda_runtime
  source_dir    = local.lambda_source_dir

  memory_size           = var.lambda_memory_size
  timeout               = var.lambda_timeout
  log_retention_days    = var.log_retention_days
  environment_variables = local.lambda_environment
  policy_statements     = local.policy_update_article

  tags = merge(local.common_tags, { Component = "api", Route = "PUT /articles/{id}" })
}

module "delete_article" {
  source = "./modules/lambda-function"

  function_name = "${local.name_prefix}-delete-article"
  description   = "DELETE /articles/{id} - baja de articulo (requiere JWT)"
  handler       = "articles.delete_article.lambda_handler"
  runtime       = var.lambda_runtime
  source_dir    = local.lambda_source_dir

  memory_size           = var.lambda_memory_size
  timeout               = var.lambda_timeout
  log_retention_days    = var.log_retention_days
  environment_variables = local.lambda_environment
  policy_statements     = local.policy_delete_article

  tags = merge(local.common_tags, { Component = "api", Route = "DELETE /articles/{id}" })
}
