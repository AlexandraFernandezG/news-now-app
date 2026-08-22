###############################################################################
# AWS WAF - proteccion de la app publica
#
# Scope CLOUDFRONT => el Web ACL DEBE vivir en us-east-1, de ahi el provider
# con alias. Se asocia unicamente a la distribucion de la app publica: es la
# que recibe los picos de trafico de promocion via influencers.
#
# La app de administracion no lleva WAF en esta fase; su superficie real
# (la API) esta protegida por el authorizer de Cognito.
###############################################################################

resource "aws_wafv2_web_acl" "public_app" {
  provider = aws.us_east_1

  name        = "${local.name_prefix}-public-app"
  description = "Rate limiting por IP para la app publica de NewsNow"
  scope       = "CLOUDFRONT"

  # Por defecto se deja pasar: el objetivo es frenar abuso, no filtrar trafico
  # legitimo de un pico de audiencia.
  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        # Mas de `limit` peticiones desde una misma IP dentro de la ventana
        # de evaluacion => bloqueo hasta que el ritmo vuelve por debajo.
        limit                 = var.waf_rate_limit
        aggregate_key_type    = "IP"
        evaluation_window_sec = var.waf_rate_limit_window_seconds
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${replace(local.name_prefix, "-", "")}RateLimitPerIp"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${replace(local.name_prefix, "-", "")}PublicAppWebAcl"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, { Component = "public-app" })
}
