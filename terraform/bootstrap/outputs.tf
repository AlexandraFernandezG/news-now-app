output "state_bucket_name" {
  description = "Bucket S3 que aloja el state remoto. Debe coincidir con terraform/backend.tf."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN del bucket de state."
  value       = aws_s3_bucket.tfstate.arn
}

output "lock_table_name" {
  description = "Tabla DynamoDB usada para el locking del state."
  value       = aws_dynamodb_table.tflock.name
}

output "lock_table_arn" {
  description = "ARN de la tabla de locking."
  value       = aws_dynamodb_table.tflock.arn
}

output "github_actions_role_arn" {
  description = "ARN del rol que asume GitHub Actions via OIDC (null si no se habilito)."
  value       = try(aws_iam_role.github_actions[0].arn, null)
}

output "backend_config" {
  description = "Bloque listo para pegar/verificar en terraform/backend.tf."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.tfstate.id}"
        key            = "${var.project_name}/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.tflock.name}"
        encrypt        = true
      }
    }
  EOT
}
