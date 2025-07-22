# =============================================================================
# Outputs for Automated Application Performance Monitoring Infrastructure
# 
# This file defines all output values that provide information about
# the created resources and their configuration details.
# =============================================================================

# =============================================================================
# SNS Topic Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for performance alerts"
  value       = aws_sns_topic.performance_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic used for performance alerts"
  value       = aws_sns_topic.performance_alerts.name
}

# =============================================================================
# Lambda Function Outputs
# =============================================================================

output "lambda_function_arn" {
  description = "ARN of the Lambda function processing performance events"
  value       = aws_lambda_function.performance_processor.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function processing performance events"
  value       = aws_lambda_function.performance_processor.function_name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# =============================================================================
# CloudWatch Alarms Outputs
# =============================================================================

output "latency_alarm_names" {
  description = "Names of CloudWatch alarms monitoring application latency"
  value = {
    for service, alarm in aws_cloudwatch_metric_alarm.high_latency : 
    service => alarm.alarm_name
  }
}

output "error_rate_alarm_names" {
  description = "Names of CloudWatch alarms monitoring application error rates"
  value = {
    for service, alarm in aws_cloudwatch_metric_alarm.high_error_rate : 
    service => alarm.alarm_name
  }
}

output "throughput_alarm_names" {
  description = "Names of CloudWatch alarms monitoring application throughput"
  value = {
    for service, alarm in aws_cloudwatch_metric_alarm.low_throughput : 
    service => alarm.alarm_name
  }
}

output "all_alarm_arns" {
  description = "ARNs of all created CloudWatch alarms"
  value = concat(
    [for alarm in aws_cloudwatch_metric_alarm.high_latency : alarm.arn],
    [for alarm in aws_cloudwatch_metric_alarm.high_error_rate : alarm.arn],
    [for alarm in aws_cloudwatch_metric_alarm.low_throughput : alarm.arn]
  )
}

# =============================================================================
# EventBridge Outputs
# =============================================================================

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule routing CloudWatch alarm state changes"
  value       = aws_cloudwatch_event_rule.alarm_state_change.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule routing CloudWatch alarm state changes"
  value       = aws_cloudwatch_event_rule.alarm_state_change.name
}

# =============================================================================
# CloudWatch Dashboard Outputs
# =============================================================================

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for performance monitoring"
  value       = aws_cloudwatch_dashboard.performance_monitoring.dashboard_name
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.performance_monitoring.dashboard_name}"
}

# =============================================================================
# Application Signals Outputs
# =============================================================================

output "application_signals_log_group_name" {
  description = "Name of the CloudWatch log group for Application Signals data"
  value       = aws_cloudwatch_log_group.application_signals.name
}

output "application_signals_log_group_arn" {
  description = "ARN of the CloudWatch log group for Application Signals data"
  value       = aws_cloudwatch_log_group.application_signals.arn
}

output "monitored_services" {
  description = "List of application services being monitored"
  value       = var.application_services
}

# =============================================================================
# Configuration Summary Outputs
# =============================================================================

output "alarm_thresholds" {
  description = "Summary of configured alarm thresholds"
  value = {
    latency_ms              = var.latency_threshold_ms
    error_rate_percent      = var.error_rate_threshold_percent
    throughput_requests     = var.throughput_threshold_requests
    alarm_period_seconds    = var.alarm_period
  }
}

output "monitoring_configuration" {
  description = "Summary of monitoring configuration"
  value = {
    project_name                        = var.project_name
    environment                         = var.environment
    application_services               = var.application_services
    notification_email                 = var.notification_email != "" ? "configured" : "not_configured"
    lambda_log_retention_days          = var.lambda_log_retention_days
    application_signals_log_retention_days = var.application_signals_log_retention_days
  }
}

# =============================================================================
# Resource Identification Outputs
# =============================================================================

output "resource_prefix" {
  description = "Prefix used for naming all resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for resource uniqueness"
  value       = random_string.suffix.result
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

# =============================================================================
# Testing and Validation Outputs
# =============================================================================

output "test_commands" {
  description = "CLI commands to test the monitoring system"
  value = {
    trigger_test_alarm = "aws cloudwatch set-alarm-state --alarm-name ${aws_cloudwatch_metric_alarm.high_latency[var.application_services[0]].alarm_name} --state-value ALARM --state-reason 'Manual test of monitoring system'"
    reset_test_alarm   = "aws cloudwatch set-alarm-state --alarm-name ${aws_cloudwatch_metric_alarm.high_latency[var.application_services[0]].alarm_name} --state-value OK --state-reason 'Manual test completion'"
    check_lambda_logs  = "aws logs describe-log-groups --log-group-name-prefix /aws/lambda/${aws_lambda_function.performance_processor.function_name}"
    view_dashboard     = "aws cloudwatch get-dashboard --dashboard-name ${aws_cloudwatch_dashboard.performance_monitoring.dashboard_name}"
  }
}

# =============================================================================
# Integration Outputs
# =============================================================================

output "integration_endpoints" {
  description = "Endpoints and ARNs for integrating with external systems"
  value = {
    sns_topic_arn        = aws_sns_topic.performance_alerts.arn
    lambda_function_arn  = aws_lambda_function.performance_processor.arn
    eventbridge_rule_arn = aws_cloudwatch_event_rule.alarm_state_change.arn
  }
}

# =============================================================================
# Cost Tracking Outputs
# =============================================================================

output "cost_allocation_tags" {
  description = "Tags applied to resources for cost allocation and tracking"
  value       = local.common_tags
}

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the monitoring infrastructure"
  value = {
    description = "Estimated costs based on moderate usage"
    components = {
      lambda_invocations      = "$1-5/month (based on alarm frequency)"
      cloudwatch_alarms      = "$${length(var.application_services) * 3 * 0.10}/month (${length(var.application_services) * 3} alarms)"
      sns_notifications      = "$0.50-2/month (based on alert frequency)"
      cloudwatch_logs        = "$2-10/month (based on log volume)"
      eventbridge_events     = "$1-3/month (based on event volume)"
      dashboard              = "$3/month"
    }
    total_estimated_range = "$${7 + length(var.application_services) * 3 * 0.10}-${23 + length(var.application_services) * 3 * 0.10}/month"
    notes = [
      "Costs vary significantly based on application traffic and alert frequency",
      "Application Signals pricing is based on ingested metrics volume",
      "Lambda costs depend on execution frequency and duration",
      "CloudWatch Logs costs depend on ingestion and retention volume"
    ]
  }
}

# =============================================================================
# Security Information Outputs
# =============================================================================

output "security_summary" {
  description = "Summary of security configurations applied"
  value = {
    lambda_execution_role = {
      arn         = aws_iam_role.lambda_execution_role.arn
      permissions = "CloudWatch read, SNS publish, Auto Scaling read/write"
    }
    encryption = {
      sns_topic_encrypted        = "Server-side encryption enabled"
      cloudwatch_logs_encrypted  = var.enable_encryption_at_rest ? "Encryption at rest enabled" : "Default encryption"
    }
    network_security = {
      lambda_vpc      = "Runs in AWS managed VPC (no custom VPC configuration required)"
      sns_access      = "Topic policy restricts access to EventBridge and Lambda"
    }
  }
}

# =============================================================================
# Troubleshooting Outputs
# =============================================================================

output "troubleshooting_resources" {
  description = "Resources and commands useful for troubleshooting"
  value = {
    lambda_function_url       = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.performance_processor.function_name}"
    cloudwatch_alarms_url     = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:"
    eventbridge_rules_url     = "https://${data.aws_region.current.name}.console.aws.amazon.com/events/home?region=${data.aws_region.current.name}#/rules"
    application_signals_url   = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#application-signals:services"
    lambda_logs_command       = "aws logs tail /aws/lambda/${aws_lambda_function.performance_processor.function_name} --follow"
    check_sns_subscriptions   = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.performance_alerts.arn}"
  }
}