variable "bucket_name" {
  description = "Nombre del bucket S3 privado que aloja los assets de la SPA."
  type        = string
}

variable "comment" {
  description = "Comentario descriptivo de la distribucion CloudFront."
  type        = string
  default     = ""
}

variable "default_root_object" {
  description = "Objeto servido en la raiz de la distribucion."
  type        = string
  default     = "index.html"
}

variable "spa_fallback_document" {
  description = "Documento devuelto (con codigo 200) ante 403/404 para que React Router resuelva la ruta en cliente."
  type        = string
  default     = "/index.html"
}

variable "price_class" {
  description = "Price class de CloudFront."
  type        = string
  default     = "PriceClass_100"
}

variable "web_acl_arn" {
  description = "ARN del Web ACL de WAFv2 (scope CLOUDFRONT) a asociar. null = sin WAF."
  type        = string
  default     = null
}

variable "error_caching_min_ttl" {
  description = "Segundos que CloudFront cachea las respuestas de error reescritas."
  type        = number
  default     = 10
}

variable "enable_versioning" {
  description = "Habilita el versionado del bucket de assets para poder revertir un despliegue."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags aplicados a los recursos del modulo."
  type        = map(string)
  default     = {}
}
