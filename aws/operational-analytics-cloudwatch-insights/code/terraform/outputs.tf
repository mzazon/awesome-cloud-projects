# Outputs for Operational Analytics with CloudWatch Insights
# This file defines the outputs that will be displayed after terraform apply

output "log_group_name" {
  description = "Name of the CloudWatch log group created for analytics"
  value       = aws_cloudwatch_log_group.operational_analytics.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.operational_analytics.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function for log generation"
  value       = aws_lambda_function.log_generator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for log generation"
  value       = aws_lambda_function.log_generator.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for operational alerts"
  value       = aws_sns_topic.operational_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for operational alerts"
  value       = aws_sns_topic.operational_alerts.name
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.operational_analytics.dashboard_name
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.operational_analytics.dashboard_name}"
}

output "cloudwatch_insights_url" {
  description = "URL to access CloudWatch Logs Insights for the log group"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:logs-insights$3FqueryDetail$3D~(end~0~start~-3600~timeType~'RELATIVE~unit~'seconds~editorString~'fields*20*40timestamp*2c*20*40message*0a*7c*20filter*20*40message*20like*20*2fERROR*2f*0a*7c*20stats*20count*28*29*20as*20error_count*20by*20bin*285m*29*0a*7c*20sort*20*40timestamp*20desc~isLiveTail~false~queryId~'~source~(~'${replace(aws_cloudwatch_log_group.operational_analytics.name, "/", "*2f")}))"
}

output "error_rate_alarm_name" {
  description = "Name of the error rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.alarm_name
}

output "log_volume_alarm_name" {
  description = "Name of the log volume CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_log_volume.alarm_name
}

output "anomaly_detector_enabled" {
  description = "Whether anomaly detection is enabled"
  value       = var.enable_anomaly_detection
}

output "anomaly_alarm_name" {
  description = "Name of the anomaly detection alarm (if enabled)"
  value       = var.enable_anomaly_detection ? aws_cloudwatch_metric_alarm.log_ingestion_anomaly[0].alarm_name : null
}

output "log_retention_days" {
  description = "Number of days logs are retained in CloudWatch"
  value       = aws_cloudwatch_log_group.operational_analytics.retention_in_days
}

output "metric_filters" {
  description = "List of metric filters created for log analysis"
  value = [
    {
      name      = aws_cloudwatch_log_metric_filter.error_rate.name
      pattern   = aws_cloudwatch_log_metric_filter.error_rate.pattern
      namespace = "OperationalAnalytics"
      metric    = "ErrorRate"
    },
    {
      name      = aws_cloudwatch_log_metric_filter.log_volume.name
      pattern   = aws_cloudwatch_log_metric_filter.log_volume.pattern
      namespace = "OperationalAnalytics"
      metric    = "LogVolume"
    }
  ]
}

output "sample_insights_queries" {
  description = "Sample CloudWatch Logs Insights queries for operational analytics"
  value = {
    error_analysis = "fields @timestamp, @message, @logStream | filter @message like /ERROR/ | stats count() as error_count by bin(5m) | sort @timestamp desc | limit 50"
    
    performance_monitoring = "fields @timestamp, @message | filter @message like /response_time/ | parse @message '\"response_time\": *' as response_time | stats avg(response_time) as avg_response_time, max(response_time) as max_response_time by bin(1m) | sort @timestamp desc"
    
    user_activity = "fields @timestamp, @message | filter @message like /user_id/ | parse @message '\"user_id\": \"*\"' as user_id | stats count() as activity_count by user_id | sort activity_count desc | limit 20"
    
    error_by_endpoint = "fields @timestamp, @message | filter @message like /ERROR/ and @message like /endpoint/ | parse @message '\"endpoint\": \"*\"' as endpoint | stats count() as error_count by endpoint | sort error_count desc | limit 10"
    
    high_response_times = "fields @timestamp, @message | filter @message like /response_time/ | parse @message '\"response_time\": *' as response_time | filter response_time > 1000 | sort @timestamp desc | limit 100"
  }
}

output "cost_optimization_info" {
  description = "Information about cost optimization measures implemented"
  value = {
    log_retention_days    = var.log_retention_days
    log_volume_threshold  = var.log_volume_threshold
    log_group_class      = "STANDARD"
    volume_monitoring    = "Enabled via LogVolumeFilter metric filter and alarm"
  }
}

output "deployment_commands" {
  description = "Useful commands for testing and managing the deployment"
  value = {
    invoke_log_generator = "aws lambda invoke --function-name ${aws_lambda_function.log_generator.function_name} --payload '{}' output.txt"
    
    view_logs = "aws logs tail ${aws_cloudwatch_log_group.operational_analytics.name} --follow"
    
    start_insights_query = "aws logs start-query --log-group-name ${aws_cloudwatch_log_group.operational_analytics.name} --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s) --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | stats count() as error_count by bin(5m) | sort @timestamp desc'"
    
    check_alarm_state = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.high_error_rate.alarm_name}"
  }
}

output "resource_summary" {
  description = "Summary of all resources created"
  value = {
    cloudwatch_log_group     = aws_cloudwatch_log_group.operational_analytics.name
    lambda_function         = aws_lambda_function.log_generator.function_name
    iam_role               = aws_iam_role.lambda_role.name
    sns_topic              = aws_sns_topic.operational_alerts.name
    dashboard              = aws_cloudwatch_dashboard.operational_analytics.dashboard_name
    metric_filters         = length([aws_cloudwatch_log_metric_filter.error_rate, aws_cloudwatch_log_metric_filter.log_volume])
    cloudwatch_alarms      = 2 + (var.enable_anomaly_detection ? 1 : 0)
    anomaly_detectors      = var.enable_anomaly_detection ? 1 : 0
  }
}