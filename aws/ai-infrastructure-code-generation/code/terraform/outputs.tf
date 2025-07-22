# Output Values for AI-Powered Infrastructure Code Generation
# These outputs provide important information about the deployed infrastructure

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for template storage"
  value       = aws_s3_bucket.template_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for template storage"
  value       = aws_s3_bucket.template_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.template_bucket.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.template_bucket.bucket_regional_domain_name
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function for template processing"
  value       = aws_lambda_function.template_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for template processing"
  value       = aws_lambda_function.template_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.template_processor.invoke_arn
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.template_processor.last_modified
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.template_processor.version
}

# IAM Role Information
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Log Group Information
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_log_group.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_log_group.arn
}

# SNS Topic Information (conditional)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.template_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications (if enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.template_notifications[0].name : null
}

# Template Upload Instructions
output "template_upload_commands" {
  description = "AWS CLI commands for uploading templates"
  value = {
    # Standard template upload
    upload_template = "aws s3 cp your-template.json s3://${aws_s3_bucket.template_bucket.bucket}/templates/"
    
    # Auto-deploy template upload
    auto_deploy_template = "aws s3 cp your-template.json s3://${aws_s3_bucket.template_bucket.bucket}/${var.auto_deploy_prefix}"
    
    # List validation results
    list_validation_results = "aws s3 ls s3://${aws_s3_bucket.template_bucket.bucket}/validation-results/"
    
    # Download validation result
    download_validation = "aws s3 cp s3://${aws_s3_bucket.template_bucket.bucket}/validation-results/your-template-validation.json ./"
  }
}

# Environment Configuration
output "environment_variables" {
  description = "Environment variables for the Lambda function"
  value = {
    BUCKET_NAME           = aws_s3_bucket.template_bucket.bucket
    AUTO_DEPLOY_PREFIX    = var.auto_deploy_prefix
    ENABLE_AUTO_DEPLOYMENT = var.enable_auto_deployment
    ENVIRONMENT           = var.environment
    APPLICATION_NAME      = var.application_name
  }
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

# Resource URLs and ARNs for CloudFormation
output "cloudwatch_logs_console_url" {
  description = "URL to view Lambda function logs in CloudWatch console"
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_log_group.name, "/", "$252F")}"
}

output "s3_console_url" {
  description = "URL to view S3 bucket in AWS console"
  value = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.template_bucket.bucket}?region=${data.aws_region.current.name}"
}

output "lambda_console_url" {
  description = "URL to view Lambda function in AWS console"
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.template_processor.function_name}"
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    application_name = var.application_name
    environment     = var.environment
    bucket_name     = aws_s3_bucket.template_bucket.bucket
    lambda_function = aws_lambda_function.template_processor.function_name
    lambda_runtime  = var.lambda_runtime
    lambda_timeout  = var.lambda_timeout
    lambda_memory   = var.lambda_memory_size
    versioning_enabled = var.enable_s3_versioning
    encryption_enabled = var.enable_s3_encryption
    sns_notifications  = var.enable_sns_notifications
    auto_deployment   = var.enable_auto_deployment
    vpc_enabled       = var.enable_vpc_config
    log_retention_days = var.log_retention_days
  }
}

# Template Processing Workflow
output "workflow_instructions" {
  description = "Instructions for using the template processing workflow"
  value = {
    step_1 = "Upload CloudFormation templates to s3://${aws_s3_bucket.template_bucket.bucket}/templates/"
    step_2 = "Lambda function will automatically validate templates and store results in validation-results/"
    step_3 = "For auto-deployment, upload templates to s3://${aws_s3_bucket.template_bucket.bucket}/${var.auto_deploy_prefix}"
    step_4 = "Check CloudWatch logs at ${aws_cloudwatch_log_group.lambda_log_group.name} for processing details"
    step_5 = var.enable_sns_notifications ? "Email notifications will be sent to ${var.notification_email}" : "Enable SNS notifications for email alerts"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    s3_public_access_blocked = true
    s3_encryption_enabled   = var.enable_s3_encryption
    s3_encryption_algorithm = var.enable_s3_encryption ? var.s3_encryption_algorithm : "none"
    iam_role_least_privilege = true
    cloudwatch_logging      = true
    vpc_isolation          = var.enable_vpc_config
  }
}

# Next Steps and Resources
output "next_steps" {
  description = "Next steps for setting up Amazon Q Developer integration"
  value = {
    install_aws_toolkit = "Install AWS Toolkit extension in VS Code from https://marketplace.visualstudio.com/items?itemName=AmazonWebServices.aws-toolkit-vscode"
    setup_q_developer   = "Configure Amazon Q Developer following https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/q-in-IDE-setup.html"
    infrastructure_composer = "Access AWS Infrastructure Composer at https://console.aws.amazon.com/composer"
    sample_templates    = "View sample templates and documentation in s3://${aws_s3_bucket.template_bucket.bucket}/documentation/"
    monitoring_logs     = "Monitor template processing in CloudWatch logs: ${aws_cloudwatch_log_group.lambda_log_group.name}"
  }
}