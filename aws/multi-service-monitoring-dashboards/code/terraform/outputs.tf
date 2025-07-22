# Outputs for Advanced Multi-Service Monitoring Dashboards
# This file defines all outputs from the monitoring infrastructure

# ================================
# GENERAL OUTPUTS
# ================================

output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = local.resource_prefix
}

# ================================
# IAM OUTPUTS
# ================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# ================================
# SNS OUTPUTS
# ================================

output "sns_topic_arns" {
  description = "ARNs of all SNS topics"
  value = {
    critical = aws_sns_topic.critical_alerts.arn
    warning  = aws_sns_topic.warning_alerts.arn
    info     = aws_sns_topic.info_alerts.arn
  }
}

output "sns_topic_names" {
  description = "Names of all SNS topics"
  value = {
    critical = aws_sns_topic.critical_alerts.name
    warning  = aws_sns_topic.warning_alerts.name
    info     = aws_sns_topic.info_alerts.name
  }
}

output "critical_alerts_topic_arn" {
  description = "ARN of the critical alerts SNS topic"
  value       = aws_sns_topic.critical_alerts.arn
}

output "warning_alerts_topic_arn" {
  description = "ARN of the warning alerts SNS topic"
  value       = aws_sns_topic.warning_alerts.arn
}

output "info_alerts_topic_arn" {
  description = "ARN of the info alerts SNS topic"
  value       = aws_sns_topic.info_alerts.arn
}

# ================================
# LAMBDA FUNCTION OUTPUTS
# ================================

output "lambda_function_arns" {
  description = "ARNs of all Lambda functions"
  value = {
    business_metrics       = aws_lambda_function.business_metrics.arn
    infrastructure_health  = aws_lambda_function.infrastructure_health.arn
    cost_monitoring       = aws_lambda_function.cost_monitoring.arn
  }
}

output "lambda_function_names" {
  description = "Names of all Lambda functions"
  value = {
    business_metrics       = aws_lambda_function.business_metrics.function_name
    infrastructure_health  = aws_lambda_function.infrastructure_health.function_name
    cost_monitoring       = aws_lambda_function.cost_monitoring.function_name
  }
}

output "business_metrics_function_name" {
  description = "Name of the business metrics Lambda function"
  value       = aws_lambda_function.business_metrics.function_name
}

output "infrastructure_health_function_name" {
  description = "Name of the infrastructure health Lambda function"
  value       = aws_lambda_function.infrastructure_health.function_name
}

output "cost_monitoring_function_name" {
  description = "Name of the cost monitoring Lambda function"
  value       = aws_lambda_function.cost_monitoring.function_name
}

# ================================
# CLOUDWATCH LOG GROUP OUTPUTS
# ================================

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = {
    business_metrics       = aws_cloudwatch_log_group.business_metrics_logs.name
    infrastructure_health  = aws_cloudwatch_log_group.infrastructure_health_logs.name
    cost_monitoring       = aws_cloudwatch_log_group.cost_monitoring_logs.name
  }
}

output "log_retention_days" {
  description = "Log retention period in days"
  value       = var.log_retention_days
}

# ================================
# EVENTBRIDGE OUTPUTS
# ================================

output "eventbridge_rules" {
  description = "EventBridge rules for scheduled monitoring"
  value = {
    business_metrics       = aws_cloudwatch_event_rule.business_metrics_schedule.name
    infrastructure_health  = aws_cloudwatch_event_rule.infrastructure_health_schedule.name
    cost_monitoring       = aws_cloudwatch_event_rule.cost_monitoring_schedule.name
  }
}

output "monitoring_schedules" {
  description = "Monitoring schedules for each function"
  value = {
    business_metrics       = var.metric_collection_schedule
    infrastructure_health  = var.infrastructure_health_schedule
    cost_monitoring       = var.cost_monitoring_schedule
  }
}

# ================================
# CLOUDWATCH DASHBOARD OUTPUTS
# ================================

output "dashboard_names" {
  description = "Names of all CloudWatch dashboards"
  value = {
    infrastructure = aws_cloudwatch_dashboard.infrastructure_dashboard.dashboard_name
    business      = aws_cloudwatch_dashboard.business_dashboard.dashboard_name
    executive     = aws_cloudwatch_dashboard.executive_dashboard.dashboard_name
    operations    = aws_cloudwatch_dashboard.operations_dashboard.dashboard_name
  }
}

output "dashboard_urls" {
  description = "URLs to access CloudWatch dashboards"
  value = {
    infrastructure = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.infrastructure_dashboard.dashboard_name}"
    business      = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.business_dashboard.dashboard_name}"
    executive     = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.executive_dashboard.dashboard_name}"
    operations    = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.operations_dashboard.dashboard_name}"
  }
}

# ================================
# CLOUDWATCH ALARM OUTPUTS
# ================================

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring"
  value = {
    revenue_anomaly         = var.anomaly_detection_enabled ? aws_cloudwatch_metric_alarm.revenue_anomaly_alarm[0].alarm_name : null
    response_time_anomaly   = var.anomaly_detection_enabled ? aws_cloudwatch_metric_alarm.response_time_anomaly_alarm[0].alarm_name : null
    infrastructure_health   = aws_cloudwatch_metric_alarm.infrastructure_health_alarm.alarm_name
  }
}

output "anomaly_detection_enabled" {
  description = "Whether anomaly detection is enabled"
  value       = var.anomaly_detection_enabled
}

output "anomaly_detection_band" {
  description = "Anomaly detection band (standard deviations)"
  value       = var.anomaly_detection_band
}

# ================================
# MONITORING CONFIGURATION OUTPUTS
# ================================

output "custom_metric_namespaces" {
  description = "Custom metric namespaces being used"
  value       = var.custom_metric_namespaces
}

output "business_unit" {
  description = "Business unit for metrics tracking"
  value       = var.business_unit
}

output "monitoring_configuration" {
  description = "Complete monitoring configuration summary"
  value = {
    project_name                = var.project_name
    environment                = var.environment
    business_unit              = var.business_unit
    anomaly_detection_enabled  = var.anomaly_detection_enabled
    detailed_monitoring_enabled = var.enable_detailed_monitoring
    cost_monitoring_enabled    = true
    cross_region_enabled       = var.enable_cross_region_monitoring
    dashboard_count           = 4
    lambda_function_count     = 3
    sns_topic_count          = 3
    alarm_count              = var.anomaly_detection_enabled ? 3 : 1
  }
}

# ================================
# COST MONITORING OUTPUTS
# ================================

output "cost_monitoring_enabled" {
  description = "Whether cost monitoring is enabled"
  value       = true
}

output "cost_anomaly_detection_enabled" {
  description = "Whether cost anomaly detection is enabled"
  value       = var.enable_cost_anomaly_detection
}

# ================================
# SECURITY OUTPUTS
# ================================

output "iam_policies_attached" {
  description = "IAM policies attached to the Lambda execution role"
  value = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "Custom CloudWatch and Service Access Policy"
  ]
}

output "security_configuration" {
  description = "Security configuration summary"
  value = {
    least_privilege_iam     = true
    encrypted_logs         = false  # CloudWatch Logs encryption not enabled by default
    vpc_configuration      = false  # Lambda functions not in VPC
    resource_based_policies = false  # No resource-based policies configured
  }
}

# ================================
# OPERATIONAL OUTPUTS
# ================================

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email
  sensitive   = true
}

output "lambda_configuration" {
  description = "Lambda function configuration details"
  value = {
    runtime      = "python3.9"
    timeout      = var.lambda_timeout
    memory_size  = var.lambda_memory_size
    architecture = "x86_64"
  }
}

output "dashboard_period" {
  description = "Default period for dashboard widgets"
  value       = var.dashboard_period
}

# ================================
# VALIDATION OUTPUTS
# ================================

output "deployment_validation" {
  description = "Validation commands for verifying deployment"
  value = {
    list_dashboards = "aws cloudwatch list-dashboards --dashboard-name-prefix ${local.resource_prefix}"
    list_alarms     = "aws cloudwatch describe-alarms --alarm-name-prefix ${local.resource_prefix}"
    list_functions  = "aws lambda list-functions --function-version ALL --query 'Functions[?starts_with(FunctionName, `${local.resource_prefix}`)].FunctionName'"
    test_business_metrics = "aws lambda invoke --function-name ${aws_lambda_function.business_metrics.function_name} --payload '{}' /tmp/test-response.json"
  }
}

# ================================
# CLEANUP OUTPUTS
# ================================

output "cleanup_commands" {
  description = "Commands for cleaning up resources"
  value = {
    delete_dashboards = "aws cloudwatch delete-dashboards --dashboard-names ${join(" ", [for k, v in local.common_tags : "${local.resource_prefix}-${title(k)}" if k != "managedby"])}"
    delete_alarms     = "aws cloudwatch delete-alarms --alarm-names $(aws cloudwatch describe-alarms --alarm-name-prefix ${local.resource_prefix} --query 'MetricAlarms[].AlarmName' --output text)"
    delete_functions  = "aws lambda delete-function --function-name ${aws_lambda_function.business_metrics.function_name} && aws lambda delete-function --function-name ${aws_lambda_function.infrastructure_health.function_name} && aws lambda delete-function --function-name ${aws_lambda_function.cost_monitoring.function_name}"
  }
}

# ================================
# RESOURCE INVENTORY
# ================================

output "resource_inventory" {
  description = "Complete inventory of created resources"
  value = {
    iam_roles           = 1
    iam_policies        = 1
    lambda_functions    = 3
    cloudwatch_log_groups = 3
    sns_topics          = 3
    sns_subscriptions   = 1 + length(var.additional_sns_subscriptions)
    eventbridge_rules   = 3
    cloudwatch_dashboards = 4
    cloudwatch_alarms   = var.anomaly_detection_enabled ? 3 : 1
    anomaly_detectors   = var.anomaly_detection_enabled ? 4 : 0
  }
}

# ================================
# TERRAFORM STATE OUTPUTS
# ================================

output "terraform_workspace" {
  description = "Current Terraform workspace"
  value       = terraform.workspace
}

output "terraform_version" {
  description = "Terraform version used for deployment"
  value       = "~> 1.0"
}

output "aws_provider_version" {
  description = "AWS provider version used"
  value       = "~> 5.0"
}