# ======================================
# Outputs for Enterprise KMS Envelope Encryption
# ======================================

# KMS Key Information
output "kms_key_id" {
  description = "The ID of the KMS customer master key"
  value       = aws_kms_key.enterprise_cmk.key_id
}

output "kms_key_arn" {
  description = "The ARN of the KMS customer master key"
  value       = aws_kms_key.enterprise_cmk.arn
}

output "kms_key_alias" {
  description = "The alias of the KMS customer master key"
  value       = aws_kms_alias.enterprise_cmk_alias.name
}

output "kms_key_rotation_enabled" {
  description = "Whether key rotation is enabled for the KMS key"
  value       = aws_kms_key.enterprise_cmk.enable_key_rotation
}

# S3 Bucket Information
output "s3_bucket_name" {
  description = "The name of the encrypted S3 bucket"
  value       = aws_s3_bucket.encrypted_data.id
}

output "s3_bucket_arn" {
  description = "The ARN of the encrypted S3 bucket"
  value       = aws_s3_bucket.encrypted_data.arn
}

output "s3_bucket_region" {
  description = "The region of the S3 bucket"
  value       = aws_s3_bucket.encrypted_data.region
}

output "s3_bucket_domain_name" {
  description = "The bucket domain name for S3 bucket"
  value       = aws_s3_bucket.encrypted_data.bucket_domain_name
}

# Lambda Function Information
output "lambda_function_name" {
  description = "The name of the key rotation monitoring Lambda function"
  value       = aws_lambda_function.key_rotation_monitor.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the key rotation monitoring Lambda function"
  value       = aws_lambda_function.key_rotation_monitor.arn
}

output "lambda_function_invoke_arn" {
  description = "The invoke ARN of the Lambda function"
  value       = aws_lambda_function.key_rotation_monitor.invoke_arn
}

output "lambda_role_arn" {
  description = "The ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# CloudWatch Information
output "cloudwatch_event_rule_name" {
  description = "The name of the CloudWatch Events rule for key rotation monitoring"
  value       = aws_cloudwatch_event_rule.key_rotation_schedule.name
}

output "cloudwatch_event_rule_arn" {
  description = "The ARN of the CloudWatch Events rule"
  value       = aws_cloudwatch_event_rule.key_rotation_schedule.arn
}

output "cloudwatch_log_group_name" {
  description = "The name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# IAM Information
output "lambda_kms_policy_arn" {
  description = "The ARN of the Lambda KMS policy"
  value       = aws_iam_policy.lambda_kms_policy.arn
}

# Testing and Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_kms_key_rotation = "aws kms get-key-rotation-status --key-id ${aws_kms_key.enterprise_cmk.key_id}"
    describe_kms_key      = "aws kms describe-key --key-id ${aws_kms_alias.enterprise_cmk_alias.name}"
    check_s3_encryption   = "aws s3api get-bucket-encryption --bucket ${aws_s3_bucket.encrypted_data.id}"
    invoke_lambda         = "aws lambda invoke --function-name ${aws_lambda_function.key_rotation_monitor.function_name} response.json"
    check_cloudwatch_rule = "aws events describe-rule --name ${aws_cloudwatch_event_rule.key_rotation_schedule.name}"
  }
}

# Sample Usage Commands
output "usage_examples" {
  description = "Example commands for using the infrastructure"
  value = {
    upload_encrypted_file = "aws s3 cp myfile.txt s3://${aws_s3_bucket.encrypted_data.id}/encrypted-data/ --sse aws:kms --sse-kms-key-id ${aws_kms_alias.enterprise_cmk_alias.name}"
    generate_data_key    = "aws kms generate-data-key --key-id ${aws_kms_alias.enterprise_cmk_alias.name} --key-spec AES_256"
    view_lambda_logs     = "aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow"
    test_lambda_function = "aws lambda invoke --function-name ${aws_lambda_function.key_rotation_monitor.function_name} --payload '{}' response.json && cat response.json"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    kms_key_created              = true
    kms_key_rotation_enabled     = aws_kms_key.enterprise_cmk.enable_key_rotation
    s3_bucket_created           = true
    s3_bucket_encryption_enabled = true
    lambda_function_deployed     = true
    monitoring_schedule         = var.monitoring_schedule
    environment                 = var.environment
    total_resources_created     = "13 resources (KMS key + alias, S3 bucket + config, Lambda + IAM, CloudWatch Events)"
  }
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the infrastructure"
  value = {
    kms_key_cost           = "$1.00 USD (Customer Master Key)"
    kms_api_requests       = "$0.03 USD per 10,000 requests"
    lambda_execution       = "~$0.20 USD (based on weekly execution)"
    cloudwatch_logs        = "~$0.50 USD (depending on log volume)"
    s3_storage             = "Variable based on data stored"
    total_estimated_base   = "~$2-5 USD per month (excluding S3 storage)"
    note                   = "Costs vary based on usage patterns and data volume"
  }
}

# Security Information
output "security_features" {
  description = "Security features implemented"
  value = {
    kms_key_rotation_enabled     = aws_kms_key.enterprise_cmk.enable_key_rotation
    s3_public_access_blocked     = "All public access blocked"
    iam_least_privilege         = "Lambda role follows least privilege principle"
    encryption_at_rest          = "S3 server-side encryption with KMS"
    encryption_in_transit       = "HTTPS/TLS for all API communications"
    cloudwatch_logging          = "Comprehensive logging for audit trails"
    automated_monitoring        = "Automated key rotation status monitoring"
  }
}