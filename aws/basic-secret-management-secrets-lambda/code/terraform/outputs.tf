# outputs.tf
# Output values for AWS basic secret management with Secrets Manager and Lambda
# These outputs provide information about created resources for verification and integration

# Secrets Manager Outputs
output "secret_arn" {
  description = "The ARN of the created Secrets Manager secret"
  value       = module.secrets_manager.secret_arn
}

output "secret_name" {
  description = "The name of the created Secrets Manager secret"
  value       = module.secrets_manager.secret_name
}

output "secret_id" {
  description = "The ID of the created Secrets Manager secret"
  value       = module.secrets_manager.secret_id
}

output "secret_version_id" {
  description = "The unique identifier of the version of the secret"
  value       = module.secrets_manager.secret_version_id
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "The name of the created Lambda function"
  value       = aws_lambda_function.secret_demo.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the created Lambda function"
  value       = aws_lambda_function.secret_demo.arn
}

output "lambda_function_invoke_arn" {
  description = "The invoke ARN of the Lambda function (for API Gateway integration)"
  value       = aws_lambda_function.secret_demo.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "The qualified ARN of the Lambda function (includes version)"
  value       = aws_lambda_function.secret_demo.qualified_arn
}

output "lambda_function_version" {
  description = "The version of the Lambda function"
  value       = aws_lambda_function.secret_demo.version
}

output "lambda_function_last_modified" {
  description = "The date the Lambda function was last modified"
  value       = aws_lambda_function.secret_demo.last_modified
}

# Optional: Lambda Function URL (if uncommented in main.tf)
# output "lambda_function_url" {
#   description = "The HTTPS URL of the Lambda function"
#   value       = aws_lambda_function_url.secret_demo_url.function_url
# }

# IAM Role Outputs
output "lambda_execution_role_arn" {
  description = "The ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "The name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "secrets_access_policy_arn" {
  description = "The ARN of the custom Secrets Manager access policy"
  value       = aws_iam_policy.secrets_access_policy.arn
}

# CloudWatch Outputs
output "lambda_log_group_name" {
  description = "The name of the CloudWatch log group for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "The ARN of the CloudWatch log group for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# CloudWatch Alarms
output "lambda_error_alarm_name" {
  description = "The name of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "lambda_duration_alarm_name" {
  description = "The name of the CloudWatch alarm for Lambda duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name
}

# Configuration Information
output "aws_region" {
  description = "The AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "The AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "extensions_layer_arn" {
  description = "The ARN of the AWS Parameters and Secrets Lambda Extension layer"
  value       = local.extensions_layer_arn
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.resource_suffix
}

# Testing and Validation Outputs
output "test_commands" {
  description = "AWS CLI commands to test the deployed resources"
  value = {
    invoke_lambda = "aws lambda invoke --function-name ${aws_lambda_function.secret_demo.function_name} --payload '{}' response.json && cat response.json"
    view_secret   = "aws secretsmanager get-secret-value --secret-id ${module.secrets_manager.secret_name} --query 'SecretString' --output text | jq ."
    check_logs    = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --order-by LastEventTime --descending --max-items 1"
  }
}

# Security Information
output "security_summary" {
  description = "Summary of security configurations applied"
  value = {
    kms_encryption           = var.kms_key_id != null ? "Custom KMS key" : "AWS managed key (aws/secretsmanager)"
    iam_least_privilege     = "Lambda role has access only to the specific secret"
    secret_recovery_window  = "${var.secret_recovery_window} days"
    extension_cache_enabled = var.extension_cache_enabled
    log_retention_days      = aws_cloudwatch_log_group.lambda_logs.retention_in_days
  }
}

# Cost Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (USD, approximate)"
  value = {
    secrets_manager = "$0.40 per secret per month"
    lambda_requests = "$0.20 per 1M requests"
    lambda_duration = "$0.0000166667 per GB-second"
    cloudwatch_logs = "$0.50 per GB ingested"
    note           = "Actual costs depend on usage patterns and AWS region"
  }
}

# Extension Configuration
output "extension_configuration" {
  description = "Configuration settings for the AWS Parameters and Secrets Lambda Extension"
  value = {
    cache_enabled     = var.extension_cache_enabled
    cache_size        = var.extension_cache_size
    max_connections   = var.extension_max_connections
    http_port         = var.extension_http_port
    layer_version     = var.lambda_extensions_layer_version
  }
}

# Resource Tags
output "applied_tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}