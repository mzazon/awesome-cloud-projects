# Outputs for AWS Config Compliance Monitoring Infrastructure
# This file defines all outputs that provide useful information after deployment

#
# AWS Config Resources
#
output "config_bucket_name" {
  description = "Name of the S3 bucket used for AWS Config data"
  value       = aws_s3_bucket.config_bucket.bucket
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket used for AWS Config data"
  value       = aws_s3_bucket.config_bucket.arn
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.config_delivery_channel.name
}

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.recorder.name
}

output "config_service_role_arn" {
  description = "ARN of the IAM role used by AWS Config service"
  value       = aws_iam_role.config_role.arn
}

#
# SNS Topic for Notifications
#
output "sns_topic_arn" {
  description = "ARN of the SNS topic for compliance notifications"
  value       = aws_sns_topic.config_topic.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for compliance notifications"
  value       = aws_sns_topic.config_topic.name
}

#
# Config Rules
#
output "aws_managed_rules" {
  description = "List of AWS managed Config rules deployed"
  value = [
    aws_config_config_rule.s3_bucket_public_access_prohibited.name,
    aws_config_config_rule.encrypted_volumes.name,
    aws_config_config_rule.root_access_key_check.name,
    aws_config_config_rule.required_tags_ec2.name
  ]
}

output "custom_lambda_rules" {
  description = "List of custom Lambda-based Config rules deployed"
  value = [
    aws_config_config_rule.security_group_restricted_ingress.name
  ]
}

#
# Lambda Functions
#
output "custom_rule_lambda_function_name" {
  description = "Name of the custom rule Lambda function"
  value       = aws_lambda_function.custom_rule_lambda.function_name
}

output "custom_rule_lambda_function_arn" {
  description = "ARN of the custom rule Lambda function"
  value       = aws_lambda_function.custom_rule_lambda.arn
}

output "remediation_lambda_function_name" {
  description = "Name of the remediation Lambda function (if enabled)"
  value       = var.enable_remediation ? aws_lambda_function.remediation_lambda[0].function_name : null
}

output "remediation_lambda_function_arn" {
  description = "ARN of the remediation Lambda function (if enabled)"
  value       = var.enable_remediation ? aws_lambda_function.remediation_lambda[0].arn : null
}

#
# CloudWatch Resources
#
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for compliance monitoring"
  value       = aws_cloudwatch_dashboard.compliance_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.compliance_dashboard.dashboard_name}"
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarms created for monitoring"
  value = var.enable_remediation ? [
    aws_cloudwatch_metric_alarm.non_compliant_resources.alarm_name,
    aws_cloudwatch_metric_alarm.remediation_errors[0].alarm_name
  ] : [
    aws_cloudwatch_metric_alarm.non_compliant_resources.alarm_name
  ]
}

#
# EventBridge Resources (Remediation)
#
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for automatic remediation (if enabled)"
  value       = var.enable_remediation ? aws_cloudwatch_event_rule.config_compliance_rule[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for automatic remediation (if enabled)"
  value       = var.enable_remediation ? aws_cloudwatch_event_rule.config_compliance_rule[0].arn : null
}

#
# IAM Resources
#
output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_role.arn
}

output "remediation_role_arn" {
  description = "ARN of the IAM role used by remediation Lambda (if enabled)"
  value       = var.enable_remediation ? aws_iam_role.remediation_role[0].arn : null
}

#
# CloudWatch Log Groups
#
output "lambda_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = var.enable_remediation ? {
    custom_rule    = aws_cloudwatch_log_group.custom_rule_lambda_logs.name
    remediation    = aws_cloudwatch_log_group.remediation_lambda_logs.name
  } : {
    custom_rule = aws_cloudwatch_log_group.custom_rule_lambda_logs.name
  }
}

#
# Configuration Information
#
output "deployment_region" {
  description = "AWS region where resources were deployed"
  value       = local.region
}

output "aws_account_id" {
  description = "AWS account ID where resources were deployed"
  value       = local.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

output "remediation_enabled" {
  description = "Whether automatic remediation is enabled"
  value       = var.enable_remediation
}

#
# Useful Commands
#
output "useful_commands" {
  description = "Useful AWS CLI commands for monitoring and management"
  value = {
    check_config_status = "aws configservice get-status"
    list_config_rules = "aws configservice describe-config-rules"
    get_compliance_summary = "aws configservice get-compliance-summary-by-config-rule"
    view_dashboard = "aws cloudwatch get-dashboard --dashboard-name ${aws_cloudwatch_dashboard.compliance_dashboard.dashboard_name}"
    check_lambda_logs = "aws logs describe-log-groups --log-group-name-prefix /aws/lambda/Config"
    trigger_rule_evaluation = "aws configservice start-config-rules-evaluation --config-rule-names ${aws_config_config_rule.s3_bucket_public_access_prohibited.name}"
  }
}

#
# Next Steps
#
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Subscribe to SNS topic for email notifications: aws sns subscribe --topic-arn ${aws_sns_topic.config_topic.arn} --protocol email --notification-endpoint your-email@example.com",
    "2. View the CloudWatch dashboard: ${aws_cloudwatch_dashboard.compliance_dashboard.dashboard_name}",
    "3. Test compliance by creating non-compliant resources",
    "4. Monitor Lambda function logs for remediation activities",
    "5. Customize Config rules based on your organization's requirements"
  ]
}