###############################################################################
# CloudWatch Alarm - errores de summarize_article
#
# threshold+ errores en una ventana de 5 minutos es indicio de un fallo
# sostenido (throttling de Bedrock, tabla inaccesible...), no un error
# aislado que el propio reintento del event source mapping ya absorbe.
###############################################################################

resource "aws_cloudwatch_metric_alarm" "summarize_article_errors" {
  alarm_name        = "${local.name_prefix}-summarize-article-errors"
  alarm_description = "${var.summarize_article_error_threshold}+ errores de summarize_article en 5 minutos"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = {
    FunctionName = module.summarize_article.function_name
  }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.summarize_article_error_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # Sin invocaciones no hay errores que reportar: "sin datos" no debe
  # considerarse un incumplimiento de la alarma.
  treat_missing_data = "notBreaching"

  tags = merge(local.common_tags, { Component = "ai", Function = "summarize-article" })
}
