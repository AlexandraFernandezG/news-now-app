output "digests_table_name" {
  description = "Nombre de la tabla DynamoDB de digests diarios."
  value       = aws_dynamodb_table.digests.name
}

output "summarize_article_function_name" {
  description = "Nombre de la Lambda que resume cada articulo."
  value       = module.summarize_article.function_name
}

output "summarize_article_dlq_url" {
  description = "URL de la DLQ de summarize_article, para inspeccionar mensajes fallidos."
  value       = aws_sqs_queue.summarize_article_dlq.url
}

output "daily_digest_function_name" {
  description = "Nombre de la Lambda que genera el digest diario."
  value       = module.daily_digest.function_name
}

output "daily_digest_schedule_name" {
  description = "Nombre de la regla de EventBridge Scheduler que dispara daily_digest."
  value       = aws_scheduler_schedule.daily_digest.name
}
