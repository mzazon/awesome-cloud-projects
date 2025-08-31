# Outputs for the Simple Log Analysis with CloudWatch Insights and SNS solution
# These outputs provide important information about the deployed resources

output "log_group_name" {
  description = "Name of the CloudWatch Log Group being monitored"
  value       = aws_cloudwatch_log_group.app_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Log Group being monitored"
  value       = aws_cloudwatch_log_group.app_logs.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for log analysis alerts"
  value       = aws_sns_topic.log_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for log analysis alerts"
  value       = aws_sns_topic.log_alerts.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function performing log analysis"
  value       = aws_lambda_function.log_analyzer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function performing log analysis"
  value       = aws_lambda_function.log_analyzer.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule that schedules log analysis"
  value       = aws_cloudwatch_event_rule.log_analysis_schedule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule that schedules log analysis"
  value       = aws_cloudwatch_event_rule.log_analysis_schedule.arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "analysis_schedule" {
  description = "Schedule expression for log analysis execution"
  value       = var.analysis_schedule
}

output "error_patterns" {
  description = "Error patterns being monitored in log messages"
  value       = var.error_patterns
}

output "query_time_range_minutes" {
  description = "Time range in minutes for log query analysis"
  value       = var.query_time_range_minutes
}

output "notification_email" {
  description = "Email address receiving SNS notifications (if configured)"
  value       = var.enable_sns_subscription && var.notification_email != "" ? var.notification_email : "Not configured"
  sensitive   = true
}

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# Usage instructions output
output "usage_instructions" {
  description = "Instructions for using the deployed log analysis solution"
  value = <<-EOT
    
    Log Analysis Solution Deployed Successfully!
    
    📊 Monitoring Configuration:
    - Log Group: ${aws_cloudwatch_log_group.app_logs.name}
    - Analysis Schedule: ${var.analysis_schedule}
    - Error Patterns: ${join(", ", var.error_patterns)}
    - Query Time Range: ${var.query_time_range_minutes} minutes
    
    📧 Notifications:
    - SNS Topic: ${aws_sns_topic.log_alerts.name}
    - Email Subscription: ${var.enable_sns_subscription && var.notification_email != "" ? "Configured" : "Not configured"}
    
    🔧 Next Steps:
    1. Add log events to the log group: ${aws_cloudwatch_log_group.app_logs.name}
    2. The Lambda function will automatically analyze logs every ${var.analysis_schedule}
    3. Check your email for SNS subscription confirmation (if configured)
    4. Monitor Lambda function logs at: /aws/lambda/${aws_lambda_function.log_analyzer.function_name}
    
    🧪 Testing:
    You can manually invoke the Lambda function to test:
    aws lambda invoke --function-name ${aws_lambda_function.log_analyzer.function_name} response.json
    
    📝 Sample Log Events:
    To test the solution, add some sample error logs using the AWS CLI:
    
    CURRENT_TIME=$$(date +%s000)
    aws logs put-log-events \
        --log-group-name ${aws_cloudwatch_log_group.app_logs.name} \
        --log-stream-name "test-stream" \
        --log-events \
        timestamp=$$CURRENT_TIME,message="ERROR: Database connection failed" \
        timestamp=$$((CURRENT_TIME + 1000)),message="CRITICAL: Application crash detected"
    
  EOT
}

# CloudWatch Logs Insights query example
output "sample_insights_query" {
  description = "Sample CloudWatch Logs Insights query for manual testing"
  value = <<-EOT
    fields @timestamp, @message
    | filter @message like /${local.error_pattern}/
    | sort @timestamp desc
    | limit 100
  EOT
}