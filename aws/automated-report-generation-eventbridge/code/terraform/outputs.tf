# Outputs for automated report generation infrastructure

# S3 Bucket Information
output "data_bucket_name" {
  description = "Name of the S3 bucket storing source data files"
  value       = aws_s3_bucket.data_bucket.id
}

output "data_bucket_arn" {
  description = "ARN of the S3 bucket storing source data files"
  value       = aws_s3_bucket.data_bucket.arn
}

output "data_bucket_domain_name" {
  description = "Domain name of the data S3 bucket"
  value       = aws_s3_bucket.data_bucket.bucket_domain_name
}

output "reports_bucket_name" {
  description = "Name of the S3 bucket storing generated reports"
  value       = aws_s3_bucket.reports_bucket.id
}

output "reports_bucket_arn" {
  description = "ARN of the S3 bucket storing generated reports"
  value       = aws_s3_bucket.reports_bucket.arn
}

output "reports_bucket_domain_name" {
  description = "Domain name of the reports S3 bucket"
  value       = aws_s3_bucket.reports_bucket.bucket_domain_name
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function for report generation"
  value       = aws_lambda_function.report_generator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for report generation"
  value       = aws_lambda_function.report_generator.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.report_generator.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.report_generator.version
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.report_generator.last_modified
}

output "lambda_function_source_code_size" {
  description = "Size of the Lambda function code in bytes"
  value       = aws_lambda_function.report_generator.source_code_size
}

# CloudWatch Logs Information
output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# IAM Role Information
output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda function execution"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda function execution"
  value       = aws_iam_role.lambda_execution_role.name
}

output "scheduler_execution_role_arn" {
  description = "ARN of the IAM role for EventBridge Scheduler execution"
  value       = aws_iam_role.scheduler_execution_role.arn
}

output "scheduler_execution_role_name" {
  description = "Name of the IAM role for EventBridge Scheduler execution"
  value       = aws_iam_role.scheduler_execution_role.name
}

# EventBridge Scheduler Information
output "schedule_name" {
  description = "Name of the EventBridge schedule for report generation"
  value       = aws_scheduler_schedule.daily_report_schedule.name
}

output "schedule_arn" {
  description = "ARN of the EventBridge schedule for report generation"
  value       = aws_scheduler_schedule.daily_report_schedule.arn
}

output "schedule_state" {
  description = "Current state of the EventBridge schedule"
  value       = aws_scheduler_schedule.daily_report_schedule.state
}

output "schedule_expression" {
  description = "Schedule expression for the EventBridge schedule"
  value       = aws_scheduler_schedule.daily_report_schedule.schedule_expression
}

output "schedule_timezone" {
  description = "Timezone for the EventBridge schedule"
  value       = aws_scheduler_schedule.daily_report_schedule.schedule_expression_timezone
}

# SES Information
output "ses_email_identity" {
  description = "Email identity configured in SES for sending reports"
  value       = var.create_ses_identity ? aws_ses_email_identity.verified_email[0].email : var.verified_email
}

output "ses_verification_status" {
  description = "Verification status of the SES email identity"
  value       = var.create_ses_identity ? "Pending - Check email for verification link" : "Manual verification required"
}

# Sample Data Information
output "sample_sales_data_key" {
  description = "S3 key for the sample sales data file"
  value       = aws_s3_object.sample_sales_data.key
}

output "sample_inventory_data_key" {
  description = "S3 key for the sample inventory data file"
  value       = aws_s3_object.sample_inventory_data.key
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_name        = var.project_name
    environment         = var.environment
    aws_region          = data.aws_region.current.name
    data_bucket         = aws_s3_bucket.data_bucket.id
    reports_bucket      = aws_s3_bucket.reports_bucket.id
    lambda_function     = aws_lambda_function.report_generator.function_name
    schedule_expression = var.schedule_expression
    schedule_timezone   = var.schedule_timezone
    verified_email      = var.verified_email
  }
}

# URLs for Easy Access
output "aws_console_urls" {
  description = "AWS Console URLs for easy access to resources"
  value = {
    lambda_function = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.report_generator.function_name}"
    data_bucket     = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.data_bucket.id}?region=${data.aws_region.current.name}"
    reports_bucket  = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.reports_bucket.id}?region=${data.aws_region.current.name}"
    cloudwatch_logs = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
    scheduler       = "https://${data.aws_region.current.name}.console.aws.amazon.com/scheduler/home?region=${data.aws_region.current.name}#schedules/${aws_scheduler_schedule.daily_report_schedule.name}"
    ses_console     = "https://${data.aws_region.current.name}.console.aws.amazon.com/ses/home?region=${data.aws_region.current.name}#/verified-identities"
  }
}

# Resource Identifiers for Integration
output "resource_identifiers" {
  description = "Resource identifiers for integration with other systems"
  value = {
    account_id                    = data.aws_caller_identity.current.account_id
    region                        = data.aws_region.current.name
    random_suffix                 = random_id.suffix.hex
    lambda_function_qualified_arn = "${aws_lambda_function.report_generator.arn}:${aws_lambda_function.report_generator.version}"
    schedule_group_name           = "default"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    s3_encryption_enabled    = var.enable_s3_encryption
    s3_versioning_enabled    = var.enable_s3_versioning
    public_access_blocked    = var.block_public_access
    iam_roles_created        = 2
    least_privilege_applied  = true
    cloudwatch_logs_enabled  = var.enable_cloudwatch_logs
  }
}

# Cost Information
output "cost_optimization_features" {
  description = "Cost optimization features enabled"
  value = {
    s3_lifecycle_enabled     = var.enable_cost_optimization
    lambda_timeout_seconds   = var.lambda_timeout
    lambda_memory_mb         = var.lambda_memory_size
    log_retention_days       = var.lambda_log_retention_days
    report_expiration_days   = var.report_expiration_days
    ia_transition_days       = var.report_transition_ia_days
    glacier_transition_days  = var.report_transition_glacier_days
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Verify the email address in SES by checking your email for a verification link",
    "2. Test the Lambda function manually using the AWS Console or CLI",
    "3. Upload your actual data files to the data bucket: ${aws_s3_bucket.data_bucket.id}",
    "4. Monitor the schedule execution in EventBridge Scheduler console",
    "5. Check CloudWatch Logs for function execution details",
    "6. Verify reports are generated in the reports bucket: ${aws_s3_bucket.reports_bucket.id}",
    "7. Set up CloudWatch alarms for monitoring Lambda function failures (optional)"
  ]
}