###############################################################################
# Parametros generales
###############################################################################

variable "project_name" {
  description = "Nombre corto del proyecto, usado como prefijo de recursos."
  type        = string
  default     = "news-now"
}

variable "environment" {
  description = "Entorno logico del despliegue."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "Region principal del despliegue (Lambdas, DynamoDB, API Gateway, Cognito)."
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos."
  type        = map(string)
  default     = {}
}

###############################################################################
# Frontends estaticos
###############################################################################

variable "public_app_bucket_name" {
  description = "Bucket S3 de la app publica de lectura. Debe ser globalmente unico."
  type        = string
  default     = "news-now-public-app"
}

variable "admin_app_bucket_name" {
  description = "Bucket S3 de la app de administracion. Debe ser globalmente unico."
  type        = string
  default     = "news-now-admin-app"
}

variable "cloudfront_price_class" {
  description = "Price class de las distribuciones CloudFront."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "price_class debe ser PriceClass_100, PriceClass_200 o PriceClass_All."
  }
}

###############################################################################
# Base de datos
###############################################################################

variable "articles_table_name" {
  description = "Nombre de la tabla DynamoDB de articulos."
  type        = string
  default     = "articles"
}

variable "enable_point_in_time_recovery" {
  description = "Habilita PITR en la tabla de articulos."
  type        = bool
  default     = true
}

###############################################################################
# Backend / Lambdas
###############################################################################

variable "lambda_runtime" {
  description = "Runtime de las Lambdas del CRUD."
  type        = string
  default     = "python3.12"
}

variable "lambda_memory_size" {
  description = "Memoria (MB) de las Lambdas del CRUD."
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Timeout (s) de las Lambdas del CRUD."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Retencion de los CloudWatch Log Groups."
  type        = number
  default     = 14
}

variable "log_level" {
  description = "Nivel de log de los handlers Python."
  type        = string
  default     = "INFO"
}

variable "cors_allow_origins" {
  description = "Origenes permitidos por CORS en el HTTP API. Restringir a los dominios CloudFront en produccion."
  type        = list(string)
  default     = ["*"]
}

variable "api_throttling_burst_limit" {
  description = "Burst de throttling por defecto del stage del HTTP API."
  type        = number
  default     = 2000
}

variable "api_throttling_rate_limit" {
  description = "Rate de throttling por defecto del stage del HTTP API (req/s)."
  type        = number
  default     = 1000
}

###############################################################################
# CloudFront delante del API Gateway
###############################################################################

variable "api_cache_ttl_seconds" {
  description = "TTL por defecto de la cache de CloudFront para GET /articles."
  type        = number
  default     = 60

  validation {
    condition     = var.api_cache_ttl_seconds >= 0 && var.api_cache_ttl_seconds <= 31536000
    error_message = "api_cache_ttl_seconds debe estar entre 0 y 31536000."
  }
}

variable "api_cache_max_ttl_seconds" {
  description = "TTL maximo de la cache de CloudFront para GET /articles."
  type        = number
  default     = 300
}

###############################################################################
# WAF (solo app publica)
###############################################################################

variable "waf_rate_limit" {
  description = "Peticiones maximas por IP dentro de la ventana de evaluacion antes de bloquear."
  type        = number
  default     = 2000
}

variable "waf_rate_limit_window_seconds" {
  description = "Ventana de evaluacion del rate limiting, en segundos."
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 120, 300, 600], var.waf_rate_limit_window_seconds)
    error_message = "WAFv2 solo admite ventanas de 60, 120, 300 o 600 segundos."
  }
}

###############################################################################
# Cognito
###############################################################################

variable "cognito_domain_prefix" {
  description = "Prefijo del dominio de Cognito Hosted UI. Se le anade el account id para garantizar unicidad global."
  type        = string
  default     = "news-now-auth"
}

variable "cognito_extra_callback_urls" {
  description = "URLs de callback adicionales del App Client (p.ej. entorno local de desarrollo)."
  type        = list(string)
  default     = ["http://localhost:5173/callback"]
}

variable "cognito_extra_logout_urls" {
  description = "URLs de logout adicionales del App Client."
  type        = list(string)
  default     = ["http://localhost:5173"]
}
