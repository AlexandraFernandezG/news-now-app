output "function_name" {
  description = "Nombre de la funcion Lambda."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN de la funcion Lambda."
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "ARN de invocacion, usado por la integracion de API Gateway."
  value       = aws_lambda_function.this.invoke_arn
}

output "role_name" {
  description = "Nombre del rol de ejecucion de la funcion."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "ARN del rol de ejecucion de la funcion."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Nombre del log group de la funcion."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN del log group de la funcion."
  value       = aws_cloudwatch_log_group.this.arn
}
