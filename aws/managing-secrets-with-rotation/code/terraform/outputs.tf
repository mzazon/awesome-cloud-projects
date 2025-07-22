# Outputs for AWS Secrets Manager Infrastructure
# This file defines output values that can be used by other Terraform configurations or for reference

output "secret_arn" {
  description = "ARN of the created secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "secret_name" {
  description = "Name of the created secret"
  value       = aws_secretsmanager_secret.db_credentials.name
}

output "secret_id" {
  description = "ID of the created secret"
  value       = aws_secretsmanager_secret.db_credentials.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.secrets_manager.arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.secrets_manager.key_id
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption"
  value       = aws_kms_alias.secrets_manager.name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda rotation function"
  value       = aws_lambda_function.rotation.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda rotation function"
  value       = aws_lambda_function.rotation.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_rotation.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_rotation.name
}

output "rotation_enabled" {
  description = "Whether automatic rotation is enabled"
  value       = var.enable_rotation
}

output "rotation_schedule" {
  description = "Schedule for automatic rotation"
  value       = var.rotation_schedule
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (if monitoring is enabled)"
  value       = var.enable_monitoring ? aws_cloudwatch_dashboard.secrets_manager[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard (if monitoring is enabled)"
  value = var.enable_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.secrets_manager[0].dashboard_name}" : null
}

output "secret_retrieval_command" {
  description = "AWS CLI command to retrieve the secret value"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.db_credentials.name} --query SecretString --output text"
}

output "manual_rotation_command" {
  description = "AWS CLI command to trigger manual rotation"
  value       = "aws secretsmanager rotate-secret --secret-id ${aws_secretsmanager_secret.db_credentials.name}"
}

output "tags" {
  description = "Tags applied to resources"
  value       = local.common_tags
}

output "account_id" {
  description = "AWS Account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS Region where resources are created"
  value       = data.aws_region.current.name
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique naming"
  value       = local.suffix
}

# Security-related outputs
output "secret_encryption_status" {
  description = "Encryption status of the secret"
  value = {
    kms_key_id     = aws_kms_key.secrets_manager.key_id
    encrypted      = true
    rotation_enabled = aws_kms_key.secrets_manager.enable_key_rotation
  }
}

output "iam_policy_summary" {
  description = "Summary of IAM policies created"
  value = {
    lambda_role_name = aws_iam_role.lambda_rotation.name
    policies_attached = [
      "service-role/AWSLambdaBasicExecutionRole",
      "${local.iam_role_name}-policy"
    ]
  }
}

# Monitoring outputs (conditional)
output "monitoring_resources" {
  description = "Monitoring resources created (if enabled)"
  value = var.enable_monitoring ? {
    dashboard_name = aws_cloudwatch_dashboard.secrets_manager[0].dashboard_name
    alarms = [
      aws_cloudwatch_metric_alarm.rotation_failure[0].alarm_name,
      aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name
    ]
  } : null
}

# Cross-account access configuration
output "cross_account_access" {
  description = "Cross-account access configuration"
  value = {
    enabled = length(var.cross_account_principals) > 0
    principals = var.cross_account_principals
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    secrets_manager = "$0.40 per secret per month"
    api_calls = "$0.05 per 10,000 API calls"
    lambda = "First 1M requests free, then $0.20 per 1M requests"
    kms = "$1.00 per key per month + $0.03 per 10,000 requests"
    cloudwatch = "Dashboard: $3.00 per month, Alarms: $0.10 per alarm per month"
  }
}