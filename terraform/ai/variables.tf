###############################################################################
# Parametros generales
#
# Mismos defaults que el stack de Fase 1 (terraform/variables.tf): mismo
# proyecto, mismo entorno, misma region. Los dos stacks tienen estado propio,
# pero deben desplegarse con los mismos valores para que el prefijo de
# nombres y la region coincidan.
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
  description = "Region del despliegue. Debe coincidir con la del stack de Fase 1: la tabla `articles`, Bedrock y las Lambdas de IA viven en la misma region."
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos."
  type        = map(string)
  default     = {}
}

###############################################################################
# Tabla `articles` (Fase 1) - se referencia por nombre, no se gestiona aqui
###############################################################################

variable "articles_table_name" {
  description = "Nombre de la tabla DynamoDB de articulos, ya creada por el stack de Fase 1 (terraform/dynamodb.tf)."
  type        = string
  default     = "articles"
}

variable "articles_publish_date_index" {
  description = "Nombre de la GSI por fecha de publicacion de la tabla `articles`, ya creada en la Fase 1."
  type        = string
  default     = "publish_date-index"
}

###############################################################################
# Tabla `digests` (Fase 2)
###############################################################################

variable "digests_table_name" {
  description = "Nombre de la tabla DynamoDB donde se guardan los digests diarios."
  type        = string
  default     = "digests"
}

variable "enable_point_in_time_recovery" {
  description = "Habilita PITR en la tabla de digests."
  type        = bool
  default     = true
}

###############################################################################
# Lambdas de IA
###############################################################################

variable "lambda_runtime" {
  description = "Runtime de las Lambdas de IA."
  type        = string
  default     = "python3.12"
}

variable "summarize_article_memory_size" {
  description = "Memoria (MB) de summarize_article."
  type        = number
  default     = 256
}

variable "summarize_article_timeout" {
  description = "Timeout (s) de summarize_article. Cubre la llamada a Bedrock (Haiku)."
  type        = number
  default     = 30
}

variable "daily_digest_memory_size" {
  description = "Memoria (MB) de daily_digest."
  type        = number
  default     = 256
}

variable "daily_digest_timeout" {
  description = "Timeout (s) de daily_digest. Cubre la Query al GSI y la llamada a Bedrock (Sonnet)."
  type        = number
  default     = 60
}

variable "log_retention_days" {
  description = "Retencion de los CloudWatch Log Groups de las Lambdas de IA (mismo criterio que la Fase 1)."
  type        = number
  default     = 14
}

variable "log_level" {
  description = "Nivel de log de los handlers Python."
  type        = string
  default     = "INFO"
}

###############################################################################
# Amazon Bedrock
#
# Los modelos Claude recientes solo admiten invocacion via inference profile
# en Bedrock (inferenceTypesSupported = INFERENCE_PROFILE, no ON_DEMAND): el
# id no es el del modelo fundacional suelto ("anthropic.claude-..."), lleva
# el prefijo de la region del profile ("eu." para enrutar solo dentro de la
# UE). Confirmado contra el catalogo real con `aws bedrock
# list-inference-profiles`. Se inyectan como variable de entorno de cada
# Lambda (HAIKU_MODEL_ID / SONNET_MODEL_ID) para poder actualizarlos sin
# redeploy del codigo.
#
# sonnet_model_id usa Claude Sonnet 4.5, no Claude Sonnet 5: al desplegar se
# comprobo que Sonnet 5 esta en disponibilidad restringida en esta cuenta
# (bedrock-runtime invoke-model devuelve AccessDeniedException, "contact AWS
# Sales", tanto en el profile "eu." como en el "global.") -- no es un tema
# de permisos IAM ni de Terraform, es una limitacion de la cuenta AWS.
# Cambiar de vuelta a Sonnet 5 en cuanto se gestione el acceso es solo
# actualizar este default, sin tocar el codigo Python.
###############################################################################

variable "haiku_model_id" {
  description = "Id del inference profile de Claude Haiku 4.5 en Bedrock, usado por summarize_article."
  type        = string
  default     = "eu.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "sonnet_model_id" {
  description = "Id del inference profile de Claude Sonnet en Bedrock, usado por daily_digest."
  type        = string
  default     = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

###############################################################################
# EventBridge Scheduler
###############################################################################

variable "daily_digest_schedule_expression" {
  description = "Expresion cron/rate de EventBridge Scheduler para disparar daily_digest"
  type        = string
  default     = "cron(0 19 * * ? *)" # 19:00 UTC todos los dias
}

###############################################################################
# CloudWatch Alarms
###############################################################################

variable "summarize_article_error_threshold" {
  description = "Numero de errores en 5 minutos que dispara la alarma de summarize_article"
  type        = number
  default     = 3
}
