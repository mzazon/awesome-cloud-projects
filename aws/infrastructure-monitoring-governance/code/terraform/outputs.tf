# Outputs for Infrastructure Monitoring with CloudTrail, Config, and Systems Manager

# S3 Bucket Information
output "monitoring_bucket_name" {
  description = "Name of the S3 bucket storing monitoring data"
  value       = aws_s3_bucket.monitoring_bucket.bucket
}

output "monitoring_bucket_arn" {
  description = "ARN of the S3 bucket storing monitoring data"
  value       = aws_s3_bucket.monitoring_bucket.arn
}

output "monitoring_bucket_region" {
  description = "Region of the S3 bucket storing monitoring data"
  value       = aws_s3_bucket.monitoring_bucket.region
}

# SNS Topic Information
output "sns_topic_name" {
  description = "Name of the SNS topic for infrastructure alerts"
  value       = aws_sns_topic.infrastructure_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for infrastructure alerts"
  value       = aws_sns_topic.infrastructure_alerts.arn
}

# CloudTrail Information
output "cloudtrail_name" {
  description = "Name of the CloudTrail"
  value       = aws_cloudtrail.infrastructure_trail.name
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = aws_cloudtrail.infrastructure_trail.arn
}

output "cloudtrail_home_region" {
  description = "Home region of the CloudTrail"
  value       = aws_cloudtrail.infrastructure_trail.home_region
}

# AWS Config Information
output "config_role_name" {
  description = "Name of the IAM role used by AWS Config"
  value       = aws_iam_role.config_role.name
}

output "config_role_arn" {
  description = "ARN of the IAM role used by AWS Config"
  value       = aws_iam_role.config_role.arn
}

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.recorder.name
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.delivery_channel.name
}

# Config Rules Information
output "config_rules" {
  description = "List of AWS Config rules created"
  value = {
    s3_bucket_public_access_prohibited = aws_config_config_rule.s3_bucket_public_access_prohibited.name
    encrypted_volumes                  = aws_config_config_rule.encrypted_volumes.name
    root_access_key_check             = aws_config_config_rule.root_access_key_check.name
    iam_password_policy               = aws_config_config_rule.iam_password_policy.name
  }
}

# Systems Manager Information
output "maintenance_window_id" {
  description = "ID of the Systems Manager maintenance window"
  value       = aws_ssm_maintenance_window.infrastructure_monitoring.id
}

output "maintenance_window_name" {
  description = "Name of the Systems Manager maintenance window"
  value       = aws_ssm_maintenance_window.infrastructure_monitoring.name
}

# CloudWatch Dashboard Information
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.infrastructure_monitoring.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.infrastructure_monitoring.dashboard_name}"
}

# Lambda Function Information (when enabled)
output "lambda_function_name" {
  description = "Name of the Lambda remediation function (if enabled)"
  value       = var.enable_automated_remediation ? aws_lambda_function.remediation_function[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda remediation function (if enabled)"
  value       = var.enable_automated_remediation ? aws_lambda_function.remediation_function[0].arn : null
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role (if enabled)"
  value       = var.enable_automated_remediation ? aws_iam_role.lambda_execution_role[0].arn : null
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function (if enabled)"
  value       = var.enable_automated_remediation ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

# EventBridge Information (when automated remediation is enabled)
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for Config compliance changes (if enabled)"
  value       = var.enable_automated_remediation ? aws_cloudwatch_event_rule.config_compliance_change[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for Config compliance changes (if enabled)"
  value       = var.enable_automated_remediation ? aws_cloudwatch_event_rule.config_compliance_change[0].arn : null
}

# Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are created"
  value       = data.aws_region.current.name
}

# Resource Naming Information
output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Compliance and Monitoring URLs
output "config_console_url" {
  description = "URL to access AWS Config console"
  value       = "https://console.aws.amazon.com/config/home?region=${data.aws_region.current.name}"
}

output "cloudtrail_console_url" {
  description = "URL to access CloudTrail console"
  value       = "https://console.aws.amazon.com/cloudtrail/home?region=${data.aws_region.current.name}"
}

output "systems_manager_console_url" {
  description = "URL to access Systems Manager console"
  value       = "https://console.aws.amazon.com/systems-manager/home?region=${data.aws_region.current.name}"
}

output "s3_console_url" {
  description = "URL to access the monitoring S3 bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.monitoring_bucket.bucket}?region=${data.aws_region.current.name}"
}

# Configuration Summary
output "monitoring_configuration_summary" {
  description = "Summary of the monitoring configuration"
  value = {
    cloudtrail_enabled               = true
    config_enabled                  = true
    systems_manager_enabled         = true
    automated_remediation_enabled   = var.enable_automated_remediation
    multi_region_trail             = aws_cloudtrail.infrastructure_trail.is_multi_region_trail
    log_file_validation_enabled    = aws_cloudtrail.infrastructure_trail.enable_log_file_validation
    global_service_events_included = aws_cloudtrail.infrastructure_trail.include_global_service_events
    config_rules_count             = 4
    dashboard_enabled              = true
  }
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs breakdown (approximate)"
  value = {
    cloudtrail_management_events = "Free for first trail"
    config_configuration_items  = "Varies based on resource count"
    config_rules                = "$2 per rule per region ($8 total)"
    s3_storage                  = "Varies based on log volume"
    sns_notifications           = "Minimal cost for standard notifications"
    lambda_executions           = var.enable_automated_remediation ? "Minimal cost for occasional executions" : "Not enabled"
    cloudwatch_dashboard        = "Free (within limits)"
    systems_manager             = "Free for basic features"
    note                        = "Actual costs depend on usage patterns and data volume"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Subscribe to SNS topic for notifications: aws sns subscribe --topic-arn ${aws_sns_topic.infrastructure_alerts.arn} --protocol email --notification-endpoint YOUR_EMAIL",
    "2. Review CloudWatch dashboard: ${aws_cloudwatch_dashboard.infrastructure_monitoring.dashboard_name}",
    "3. Monitor Config compliance: https://console.aws.amazon.com/config/home?region=${data.aws_region.current.name}#/rules",
    "4. Review CloudTrail logs in S3: ${aws_s3_bucket.monitoring_bucket.bucket}",
    "5. Configure additional Config rules as needed for your compliance requirements",
    "6. Set up lifecycle policies for S3 bucket to manage costs",
    "7. Test automated remediation by creating a non-compliant resource (if enabled)"
  ]
}