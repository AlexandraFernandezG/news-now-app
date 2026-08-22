###############################################################################
# DynamoDB - tabla de articulos
#
# On-demand: no hay que aprovisionar capacidad para picos impredecibles.
#
# Preparada para la Fase 2 (capa de IA) desde ya, porque ninguna de las dos
# cosas se puede anadir despues sin recrear/rehacer la tabla:
#   - Streams activos: el consumidor de resumenes se enganchara aqui.
#   - GSI por publish_date: soportara la query del resumen diario.
###############################################################################

locals {
  publish_date_index_name = "publish_date-index"
}

resource "aws_dynamodb_table" "articles" {
  name         = var.articles_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # Fecha de publicacion en formato YYYY-MM-DD: particiona por dia, que es
  # exactamente el patron de acceso del resumen diario de la Fase 2.
  attribute {
    name = "publish_date"
    type = "S"
  }

  # Timestamp ISO-8601 completo: ordena los articulos dentro de un mismo dia.
  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = local.publish_date_index_name
    hash_key        = "publish_date"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  # Fase 2: el stream alimentara la Lambda de resumen por articulo.
  # NEW_AND_OLD_IMAGES permite detectar si el contenido cambio realmente.
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, { Component = "database" })

  lifecycle {
    # Cambiar hash_key/range_key/streams obliga a recrear la tabla y perder
    # los datos: se bloquea explicitamente.
    prevent_destroy = true
  }
}
