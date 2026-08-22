###############################################################################
# NewsNow - Bootstrapping del backend remoto de Terraform
#
# Esta configuracion se aplica UNA SOLA VEZ y POR SEPARADO del proyecto raiz,
# usando backend local (no hay bloque `backend` aqui, a proposito: no puede
# existir el backend remoto antes de crear el bucket que lo aloja).
#
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#
# Despues, el proyecto raiz (terraform/) apunta a estos recursos via backend.tf.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = merge(
    {
      Project   = var.project_name
      ManagedBy = "terraform"
      Component = "bootstrap"
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

###############################################################################
# Bucket S3 para el state remoto
###############################################################################

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  # El state es el activo mas critico del proyecto: se protege frente a
  # `terraform destroy` accidentales sobre esta misma carpeta.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Limpieza de versiones antiguas del state para que el bucket no crezca
# indefinidamente (se conserva un mes de historico, mas que suficiente para
# recuperar un state corrupto).
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Deniega cualquier acceso que no viaje por TLS.
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

data "aws_iam_policy_document" "tfstate_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

###############################################################################
# Tabla DynamoDB para el state locking
###############################################################################

resource "aws_dynamodb_table" "tflock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

###############################################################################
# CI/CD: proveedor OIDC de GitHub + rol que asume el workflow de deploy
#
# Vive en bootstrap porque el pipeline necesita este rol para poder ejecutar
# el `terraform apply` del proyecto raiz: no puede crearselo a si mismo.
# Se desactiva dejando `github_repository = ""`.
###############################################################################

locals {
  enable_github_oidc = var.github_repository != ""
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.enable_github_oidc && var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_openid_connect_provider" "github_existing" {
  count = local.enable_github_oidc && !var.create_github_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_provider_arn = local.enable_github_oidc ? (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github_existing[0].arn
  ) : null
}

data "aws_iam_policy_document" "github_assume_role" {
  count = local.enable_github_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Solo ramas/entornos concretos de un unico repositorio pueden asumir el rol.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in var.github_subject_claims : "repo:${var.github_repository}:${s}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = local.enable_github_oidc ? 1 : 0

  name                 = "${var.project_name}-github-actions-deploy"
  description          = "Rol asumido por GitHub Actions via OIDC para desplegar NewsNow"
  assume_role_policy   = data.aws_iam_policy_document.github_assume_role[0].json
  max_session_duration = 3600
}

# Permisos del pipeline: acotados a los servicios que compone este proyecto.
# No se usa AdministratorAccess ni PowerUserAccess.
data "aws_iam_policy_document" "github_actions" {
  count = local.enable_github_oidc ? 1 : 0

  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]
  }

  statement {
    sid    = "TerraformLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [aws_dynamodb_table.tflock.arn]
  }

  statement {
    sid    = "ProvisionApplicationStack"
    effect = "Allow"
    actions = [
      "apigateway:*",
      "cloudfront:*",
      "cognito-idp:*",
      "dynamodb:*",
      "lambda:*",
      "logs:*",
      "s3:*",
      "wafv2:*",
      "tag:GetResources",
    ]
    resources = ["*"]
  }

  # IAM acotado a los roles/politicas de este proyecto: el pipeline no puede
  # crear ni modificar identidades ajenas al stack de NewsNow.
  statement {
    sid    = "ManageProjectRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PassRole",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
    ]
  }

  statement {
    sid    = "ReadOnlyIdentity"
    effect = "Allow"
    actions = [
      "iam:ListRoles",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  count = local.enable_github_oidc ? 1 : 0

  name   = "${var.project_name}-deploy"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions[0].json
}

###############################################################################
# Variables
###############################################################################

variable "aws_region" {
  description = "Region AWS donde viven el bucket de state y la tabla de locks."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Nombre corto del proyecto, usado como prefijo de recursos."
  type        = string
  default     = "news-now"
}

variable "state_bucket_name" {
  description = <<-EOT
    Nombre del bucket S3 del state remoto. Debe ser globalmente unico:
    si esta ocupado, cambia este valor y el `bucket` de terraform/backend.tf
    (o pasalo con `terraform init -backend-config="bucket=..."`).
  EOT
  type        = string
  default     = "news-now-terraform-state"
}

variable "lock_table_name" {
  description = "Nombre de la tabla DynamoDB usada para el locking del state."
  type        = string
  default     = "news-now-terraform-locks"
}

variable "github_repository" {
  description = "Repositorio 'owner/repo' autorizado a desplegar via OIDC. Vacio = no crear rol de CI/CD."
  type        = string
  default     = ""
}

variable "github_subject_claims" {
  description = "Patrones de 'sub' del token OIDC autorizados (ramas, tags o environments)."
  type        = list(string)
  default     = ["ref:refs/heads/main", "environment:production"]
}

variable "create_github_oidc_provider" {
  description = "false si el proveedor OIDC de GitHub ya existe en la cuenta (solo puede haber uno)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags adicionales aplicados a todos los recursos."
  type        = map(string)
  default     = {}
}
