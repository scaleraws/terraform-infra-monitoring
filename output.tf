output "lambda_function_name" {
  value = aws_lambda_function.backup_lambda.function_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts_topic.arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.infra_dashboard.dashboard_name
}
