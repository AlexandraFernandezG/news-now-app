###############################################################################
# Cognito - identidad de la redaccion
#
# Solo la app de administracion autentica. El User Pool emite los JWT que
# valida el authorizer nativo del HTTP API en POST/PUT/DELETE; GET /articles
# queda publico y nunca pasa por aqui.
###############################################################################

resource "aws_cognito_user_pool" "this" {
  name = "${local.name_prefix}-users"

  # El alta de redactores la hace un administrador: no hay registro abierto.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 5
      max_length = 254
    }
  }

  tags = merge(local.common_tags, { Component = "auth" })
}

# Dominio del Hosted UI. El prefijo es global en toda AWS, de ahi el sufijo
# con el account id.
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.cognito_domain_prefix}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_pool_client" "admin_app" {
  name         = "${local.name_prefix}-admin-app"
  user_pool_id = aws_cognito_user_pool.this.id

  # SPA publica: sin client secret, el flujo es Authorization Code + PKCE.
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = concat(
    ["${module.admin_app.url}/callback"],
    var.cognito_extra_callback_urls,
  )

  logout_urls = concat(
    [module.admin_app.url],
    var.cognito_extra_logout_urls,
  )

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
}
