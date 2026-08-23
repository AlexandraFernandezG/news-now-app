###############################################################################
# DynamoDB - tabla de digests diarios
#
# On-demand, igual que `articles`: el patron de escritura es un unico
# PutItem al dia por daily_digest, sin picos que aprovisionar.
###############################################################################

resource "aws_dynamodb_table" "digests" {
  name         = var.digests_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "digest_date"

  # Fecha del digest en formato YYYY-MM-DD: una particion por dia, un unico
  # item por particion.
  attribute {
    name = "digest_date"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, { Component = "database" })

  lifecycle {
    # Igual criterio que `articles` (terraform/dynamodb.tf): borrarla se pide
    # explicitamente, nunca es efecto colateral de un apply.
    prevent_destroy = true
  }
}
