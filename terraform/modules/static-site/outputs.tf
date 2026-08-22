output "bucket_name" {
  description = "Nombre del bucket de assets (destino del `aws s3 sync` del build de React)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN del bucket de assets."
  value       = aws_s3_bucket.this.arn
}

output "distribution_id" {
  description = "ID de la distribucion CloudFront (necesario para invalidaciones)."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "ARN de la distribucion CloudFront."
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Dominio publico de la distribucion."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "url" {
  description = "URL de acceso a la aplicacion."
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "origin_access_control_id" {
  description = "ID del OAC asociado a esta distribucion."
  value       = aws_cloudfront_origin_access_control.this.id
}
