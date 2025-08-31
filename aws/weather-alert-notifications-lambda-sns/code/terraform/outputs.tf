# Output values for the weather alert notifications infrastructure
# These outputs provide important information about the deployed resources

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.weather_checker.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.weather_checker.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.weather_checker.invoke_arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.weather_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.weather_notifications.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.weather_schedule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.weather_schedule.arn
}

output "iam_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "iam_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "weather_monitoring_config" {
  description = "Weather monitoring configuration summary"
  value = {
    city                   = var.city
    temperature_threshold  = var.temperature_threshold
    wind_threshold        = var.wind_threshold
    schedule_expression   = var.schedule_expression
    region               = var.aws_region
    environment          = var.environment
  }
}

output "deployment_instructions" {
  description = "Instructions for completing the deployment"
  value = <<-EOT
    Weather Alert Notifications System Deployed Successfully!
    
    Next Steps:
    1. Subscribe to SNS notifications:
       aws sns subscribe --topic-arn ${aws_sns_topic.weather_notifications.arn} --protocol email --notification-endpoint YOUR_EMAIL
    
    2. Confirm email subscription by clicking the link in the confirmation email
    
    3. Test the Lambda function:
       aws lambda invoke --function-name ${aws_lambda_function.weather_checker.function_name} --payload '{}' response.json
    
    4. Monitor CloudWatch logs:
       aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow
    
    5. Update weather API key (optional):
       aws lambda update-function-configuration --function-name ${aws_lambda_function.weather_checker.function_name} --environment Variables='{SNS_TOPIC_ARN=${aws_sns_topic.weather_notifications.arn},CITY=${var.city},TEMP_THRESHOLD=${var.temperature_threshold},WIND_THRESHOLD=${var.wind_threshold},WEATHER_API_KEY=YOUR_API_KEY}'
    
    The system will automatically check weather conditions based on your schedule: ${var.schedule_expression}
  EOT
}

output "monitoring_resources" {
  description = "Resources for monitoring the weather alert system"
  value = {
    cloudwatch_logs_url = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
    lambda_function_url = "https://${var.aws_region}.console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${aws_lambda_function.weather_checker.function_name}"
    sns_topic_url      = "https://${var.aws_region}.console.aws.amazon.com/sns/v3/home?region=${var.aws_region}#/topic/${aws_sns_topic.weather_notifications.arn}"
    eventbridge_rule_url = "https://${var.aws_region}.console.aws.amazon.com/events/home?region=${var.aws_region}#/eventbus/default/rules/${aws_cloudwatch_event_rule.weather_schedule.name}"
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = <<-EOT
    Cost Optimization Tips:
    
    1. Lambda costs scale with execution time and memory allocation
       - Current memory: ${var.lambda_memory_size} MB
       - Current timeout: ${var.lambda_timeout} seconds
    
    2. SNS charges per message published and delivered
       - Each weather check can send 0-1 messages depending on conditions
    
    3. EventBridge charges per rule evaluation
       - Current schedule: ${var.schedule_expression}
       - Consider adjusting frequency based on weather patterns
    
    4. CloudWatch Logs charges for log ingestion and storage
       - Logs are retained for 14 days by default
       - Consider shorter retention for cost savings
    
    Estimated monthly cost for hourly checks: $0.05 - $0.20
  EOT
}