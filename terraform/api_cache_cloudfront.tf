###############################################################################
# CloudFront delante del API Gateway
#
# El listado de articulos es el 99% del trafico y es identico para todos los
# lectores: cachearlo en el borde absorbe los picos sin tocar Lambda ni
# DynamoDB.
#
#   comportamiento por defecto (/*)   -> CachingDisabled  (POST/PUT/DELETE
#                                        y cualquier otra ruta pasan siempre)
#   comportamiento /articles          -> cache propia, TTL var.api_cache_ttl_seconds
#
# En el behavior de /articles se permiten todos los metodos pero solo se
# cachean GET/HEAD (`cached_methods`), asi POST /articles comparte path sin
# servirse nunca desde cache.
###############################################################################

locals {
  api_origin_id = "apigw-${aws_apigatewayv2_api.this.id}"

  # api_endpoint viene como https://<id>.execute-api.<region>.amazonaws.com
  api_origin_domain = trimprefix(aws_apigatewayv2_api.this.api_endpoint, "https://")

  # Politicas gestionadas por AWS (IDs constantes).
  # AllViewerExceptHostHeader reenvia query strings, cookies y cabeceras
  # (incluida Authorization) pero deja que CloudFront ponga el Host correcto
  # del origen, requisito de API Gateway.
  origin_request_all_viewer_except_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  cache_policy_caching_disabled         = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
}

###############################################################################
# Cache policy del listado
###############################################################################

resource "aws_cloudfront_cache_policy" "articles_list" {
  name        = "${local.name_prefix}-articles-list"
  comment     = "Cache de GET /articles con TTL de ${var.api_cache_ttl_seconds}s"
  default_ttl = var.api_cache_ttl_seconds
  max_ttl     = var.api_cache_max_ttl_seconds
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    # Los filtros del listado (fecha, paginacion) viajan en query string y
    # deben formar parte de la clave de cache.
    query_strings_config {
      query_string_behavior = "all"
    }

    # Authorization deliberadamente FUERA de la clave: GET /articles es
    # publico e identico para todos, no debe fragmentarse por usuario.
    headers_config {
      header_behavior = "none"
    }

    cookies_config {
      cookie_behavior = "none"
    }
  }
}

###############################################################################
# Distribucion
###############################################################################

resource "aws_cloudfront_distribution" "api" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix} - cache de la API de articulos"
  price_class     = var.cloudfront_price_class

  origin {
    domain_name = local.api_origin_domain
    origin_id   = local.api_origin_id

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Todo lo que no sea el listado atraviesa la CDN sin cachearse: escrituras
  # del panel de administracion, preflights CORS, rutas futuras.
  default_cache_behavior {
    target_origin_id       = local.api_origin_id
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.origin_request_all_viewer_except_host
  }

  ordered_cache_behavior {
    path_pattern           = "/articles"
    target_origin_id       = local.api_origin_id
    viewer_protocol_policy = "https-only"

    # POST /articles comparte path con el listado: se permite el metodo, pero
    # solo GET/HEAD entran en cache. El resto va siempre al origen.
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    cache_policy_id          = aws_cloudfront_cache_policy.articles_list.id
    origin_request_policy_id = local.origin_request_all_viewer_except_host
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Sin dominio propio en esta fase: se usa el certificado *.cloudfront.net.
  # Al anadir un dominio custom bastara con un acm_certificate_arn aqui y
  # minimum_protocol_version = "TLSv1.2_2021".
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, { Component = "api-cache" })
}
