# Outputs for AWS Config Auto-Remediation Infrastructure
# These outputs provide important information about the deployed resources
# for verification, integration, and operational use

# ====================================================================
# AWS CONFIG OUTPUTS
# ====================================================================

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.recorder.name
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.delivery_channel.name
}

output "config_s3_bucket_name" {
  description = "Name of the S3 bucket storing Config data"
  value       = aws_s3_bucket.config_bucket.bucket
}

output "config_s3_bucket_arn" {
  description = "ARN of the S3 bucket storing Config data"
  value       = aws_s3_bucket.config_bucket.arn
}

# ====================================================================
# IAM ROLE OUTPUTS
# ====================================================================

output "config_role_arn" {
  description = "ARN of the IAM role used by AWS Config"
  value       = aws_iam_role.config_role.arn
}

output "config_role_name" {
  description = "Name of the IAM role used by AWS Config"
  value       = aws_iam_role.config_role.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by Lambda remediation functions"
  value       = aws_iam_role.lambda_remediation_role.arn
}

output "lambda_role_name" {
  description = "Name of the IAM role used by Lambda remediation functions"
  value       = aws_iam_role.lambda_remediation_role.name
}

# ====================================================================
# LAMBDA FUNCTION OUTPUTS
# ====================================================================

output "security_group_remediation_function_name" {
  description = "Name of the security group remediation Lambda function"
  value       = aws_lambda_function.security_group_remediation.function_name
}

output "security_group_remediation_function_arn" {
  description = "ARN of the security group remediation Lambda function"
  value       = aws_lambda_function.security_group_remediation.arn
}

output "s3_remediation_function_name" {
  description = "Name of the S3 remediation Lambda function"
  value       = aws_lambda_function.s3_remediation.function_name
}

output "s3_remediation_function_arn" {
  description = "ARN of the S3 remediation Lambda function"
  value       = aws_lambda_function.s3_remediation.arn
}

# ====================================================================
# CONFIG RULES OUTPUTS
# ====================================================================

output "config_rules" {
  description = "Map of Config rule names and their enabled status"
  value = {
    security_group_ssh_restricted = var.config_rules_enabled.security_group_ssh_restricted ? (
      length(aws_config_config_rule.security_group_ssh_restricted) > 0 ?
      aws_config_config_rule.security_group_ssh_restricted[0].name : null
    ) : null
    s3_bucket_public_access_prohibited = var.config_rules_enabled.s3_bucket_public_access_prohibited ? (
      length(aws_config_config_rule.s3_bucket_public_access_prohibited) > 0 ?
      aws_config_config_rule.s3_bucket_public_access_prohibited[0].name : null
    ) : null
    root_access_key_check = var.config_rules_enabled.root_access_key_check ? (
      length(aws_config_config_rule.root_access_key_check) > 0 ?
      aws_config_config_rule.root_access_key_check[0].name : null
    ) : null
    iam_password_policy = var.config_rules_enabled.iam_password_policy ? (
      length(aws_config_config_rule.iam_password_policy) > 0 ?
      aws_config_config_rule.iam_password_policy[0].name : null
    ) : null
  }
}

output "auto_remediation_enabled" {
  description = "Whether auto-remediation is enabled for Config rules"
  value       = var.auto_remediation_enabled
}

# ====================================================================
# SNS OUTPUTS
# ====================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for compliance notifications"
  value       = aws_sns_topic.compliance_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for compliance notifications"
  value       = aws_sns_topic.compliance_notifications.name
}

output "sns_subscriptions" {
  description = "List of email addresses subscribed to compliance notifications"
  value       = var.sns_email_notifications
  sensitive   = true
}

# ====================================================================
# CLOUDWATCH OUTPUTS
# ====================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for compliance monitoring"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.compliance_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? (
    "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.compliance_dashboard[0].dashboard_name}"
  ) : null
}

output "lambda_log_groups" {
  description = "CloudWatch Log Groups for Lambda functions"
  value = {
    security_group_remediation = aws_cloudwatch_log_group.sg_remediation_logs.name
    s3_remediation            = aws_cloudwatch_log_group.s3_remediation_logs.name
  }
}

# ====================================================================
# DEPLOYMENT INFORMATION
# ====================================================================

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "deployment_environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# ====================================================================
# VALIDATION OUTPUTS
# ====================================================================

output "config_recorder_status_command" {
  description = "AWS CLI command to check Config recorder status"
  value       = "aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[*].[name,recordingGroup.allSupported]' --region ${var.aws_region}"
}

output "config_rules_status_command" {
  description = "AWS CLI command to check Config rules status"
  value       = "aws configservice describe-config-rules --query 'ConfigRules[*].[ConfigRuleName,ConfigRuleState]' --output table --region ${var.aws_region}"
}

output "compliance_summary_command" {
  description = "AWS CLI command to get compliance summary"
  value       = "aws configservice get-compliance-summary-by-config-rule --query 'ComplianceSummary' --region ${var.aws_region}"
}

output "lambda_logs_command" {
  description = "AWS CLI command to view recent Lambda execution logs"
  value       = "aws logs describe-log-streams --log-group-name '${aws_cloudwatch_log_group.sg_remediation_logs.name}' --order-by LastEventTime --descending --max-items 1 --query 'logStreams[0].logStreamName' --output text --region ${var.aws_region}"
}

# ====================================================================
# COST ESTIMATION
# ====================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployment (USD)"
  value = {
    config_recorder     = "~$2.00 per configuration item recorded"
    config_rules        = "~$2.00 per rule evaluation"
    lambda_invocations  = "~$0.20 per 1M requests + compute time"
    s3_storage         = "~$0.023 per GB stored"
    sns_notifications  = "~$0.50 per 1M notifications"
    cloudwatch_logs    = "~$0.50 per GB ingested"
    total_estimate     = "$10-50 per month for typical usage"
  }
}

# ====================================================================
# NEXT STEPS
# ====================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Start the Config recorder: aws configservice start-configuration-recorder --configuration-recorder-name ${aws_config_configuration_recorder.recorder.name} --region ${var.aws_region}",
    "2. Wait for initial configuration items to be recorded (5-10 minutes)",
    "3. Check Config rule compliance: aws configservice get-compliance-summary-by-config-rule --region ${var.aws_region}",
    "4. Test remediation by creating a non-compliant security group",
    "5. Monitor the CloudWatch dashboard for compliance metrics",
    "6. Review SNS notifications for remediation actions"
  ]
}