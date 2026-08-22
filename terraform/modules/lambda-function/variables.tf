variable "function_name" {
  description = "Nombre completo de la funcion Lambda."
  type        = string
}

variable "description" {
  description = "Descripcion de la funcion."
  type        = string
  default     = ""
}

variable "handler" {
  description = "Handler en formato 'modulo.funcion' relativo a la raiz del paquete (ej. articles.get_articles.lambda_handler)."
  type        = string
}

variable "runtime" {
  description = "Runtime de la Lambda."
  type        = string
  default     = "python3.12"
}

variable "source_dir" {
  description = "Directorio que se empaqueta como codigo de la funcion."
  type        = string
}

variable "source_excludes" {
  description = "Patrones excluidos del zip de despliegue."
  type        = list(string)
  default     = ["**/__pycache__/**", "**/*.pyc", "**/tests/**"]
}

variable "memory_size" {
  description = "Memoria (MB) asignada a la funcion."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Timeout de la funcion en segundos."
  type        = number
  default     = 10
}

variable "environment_variables" {
  description = "Variables de entorno de la funcion."
  type        = map(string)
  default     = {}
}

variable "policy_statements" {
  description = <<-EOT
    Permisos especificos de esta funcion, ademas de los de logging.
    Se traducen a una politica inline en su propio rol de ejecucion, de forma
    que cada Lambda solo puede hacer lo que necesita (minimo privilegio).
  EOT
  type = list(object({
    sid       = optional(string)
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "log_retention_days" {
  description = "Dias de retencion del log group de la funcion."
  type        = number
  default     = 14
}

variable "tracing_mode" {
  description = "Modo de X-Ray: PassThrough o Active."
  type        = string
  default     = "Active"
}

variable "tags" {
  description = "Tags aplicados a los recursos del modulo."
  type        = map(string)
  default     = {}
}
