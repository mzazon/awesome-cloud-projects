# Outputs for Log Analytics Solution
# This file defines the outputs that will be displayed after terraform apply

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.main.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.main.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function for log analysis"
  value       = aws_lambda_function.log_analyzer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for log analysis"
  value       = aws_lambda_function.log_analyzer.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled analysis"
  value       = aws_cloudwatch_event_rule.log_analysis_schedule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled analysis"
  value       = aws_cloudwatch_event_rule.log_analysis_schedule.arn
}

output "sample_data_generator_function_name" {
  description = "Name of the sample data generator Lambda function (if enabled)"
  value       = var.enable_sample_data ? aws_lambda_function.sample_data_generator[0].function_name : null
}

output "sample_log_stream_name" {
  description = "Name of the sample log stream (if enabled)"
  value       = var.enable_sample_data ? aws_cloudwatch_log_stream.sample_stream[0].name : null
}

output "cloudwatch_logs_insights_console_url" {
  description = "URL to access CloudWatch Logs Insights console for the log group"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:logs-insights$3FqueryDetail$3D~(end~0~start~-3600~timeType~'RELATIVE~unit~'seconds~editorString~'fields*20*40timestamp*2c*20*40message*0a*7c*20filter*20*40message*20like*20*2fERROR*2f*0a*7c*20stats*20count*28*29*20as*20error_count~isLiveTail~false~source~(~'${replace(aws_cloudwatch_log_group.main.name, "/", "*2f")}))"
}

output "deployment_commands" {
  description = "Commands to test the deployment"
  value = {
    test_lambda_function = "aws lambda invoke --function-name ${aws_lambda_function.log_analyzer.function_name} --payload '{}' response.json && cat response.json"
    view_logs = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.main.name} --start-time $(date -d '1 hour ago' +%s)000"
    check_sns_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.alerts.arn}"
    manual_query_example = "aws logs start-query --log-group-name ${aws_cloudwatch_log_group.main.name} --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s) --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | stats count() as error_count'"
  }
}

output "cleanup_commands" {
  description = "Commands to clean up resources (alternative to terraform destroy)"
  value = {
    delete_eventbridge_rule = "aws events remove-targets --rule ${aws_cloudwatch_event_rule.log_analysis_schedule.name} --ids 1 && aws events delete-rule --name ${aws_cloudwatch_event_rule.log_analysis_schedule.name}"
    delete_lambda_function = "aws lambda delete-function --function-name ${aws_lambda_function.log_analyzer.function_name}"
    delete_sns_topic = "aws sns delete-topic --topic-arn ${aws_sns_topic.alerts.arn}"
    delete_log_group = "aws logs delete-log-group --log-group-name ${aws_cloudwatch_log_group.main.name}"
  }
}

output "monitoring_queries" {
  description = "Useful CloudWatch Logs Insights queries for monitoring"
  value = {
    error_analysis = "fields @timestamp, @message | filter @message like /ERROR/ | stats count() as error_count by bin(5m)"
    api_performance = "fields @timestamp, @message | filter @message like /API Request/ | parse @message '* - *ms' as status, response_time | stats avg(response_time) as avg_response_time, max(response_time) as max_response_time by bin(5m)"
    warning_trends = "fields @timestamp, @message | filter @message like /WARN/ | stats count() as warning_count by bin(1h)"
    log_volume = "fields @timestamp | stats count() as log_count by bin(1h)"
    response_status_codes = "fields @timestamp, @message | filter @message like /API Request/ | parse @message '* - * - *' as endpoint, status, response_time | stats count() as request_count by status"
  }
}

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    region = data.aws_region.current.name
    account_id = data.aws_caller_identity.current.account_id
    log_group = aws_cloudwatch_log_group.main.name
    retention_days = var.log_retention_days
    lambda_function = aws_lambda_function.log_analyzer.function_name
    sns_topic = aws_sns_topic.alerts.name
    analysis_schedule = var.analysis_schedule
    notification_email = var.notification_email
    error_threshold = var.error_threshold
    analysis_window_hours = var.analysis_window_hours
    sample_data_enabled = var.enable_sample_data
  }
}