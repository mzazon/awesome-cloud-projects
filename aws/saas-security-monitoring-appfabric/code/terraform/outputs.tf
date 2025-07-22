# Output values for the centralized SaaS security monitoring infrastructure

# ==============================================================================
# S3 Bucket Outputs
# ==============================================================================

output "s3_security_logs_bucket_name" {
  description = "Name of the S3 bucket storing security logs from AppFabric"
  value       = aws_s3_bucket.security_logs.bucket
}

output "s3_security_logs_bucket_arn" {
  description = "ARN of the S3 bucket storing security logs from AppFabric"
  value       = aws_s3_bucket.security_logs.arn
}

output "s3_security_logs_bucket_domain_name" {
  description = "Bucket domain name for the security logs S3 bucket"
  value       = aws_s3_bucket.security_logs.bucket_domain_name
}

output "s3_security_logs_bucket_regional_domain_name" {
  description = "Bucket regional domain name for the security logs S3 bucket"
  value       = aws_s3_bucket.security_logs.bucket_regional_domain_name
}

# ==============================================================================
# SNS Topic Outputs
# ==============================================================================

output "sns_security_alerts_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "sns_security_alerts_topic_name" {
  description = "Name of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.name
}

output "sns_topic_subscription_arn" {
  description = "ARN of the email subscription to the security alerts topic"
  value       = var.alert_email != "" ? aws_sns_topic_subscription.email_alerts[0].arn : "No email subscription configured"
}

# ==============================================================================
# EventBridge Outputs
# ==============================================================================

output "eventbridge_custom_bus_name" {
  description = "Name of the custom EventBridge bus for security events"
  value       = aws_cloudwatch_event_bus.security_monitoring.name
}

output "eventbridge_custom_bus_arn" {
  description = "ARN of the custom EventBridge bus for security events"
  value       = aws_cloudwatch_event_bus.security_monitoring.arn
}

output "eventbridge_s3_rule_name" {
  description = "Name of the EventBridge rule for S3 security log events"
  value       = aws_cloudwatch_event_rule.s3_security_logs.name
}

output "eventbridge_s3_rule_arn" {
  description = "ARN of the EventBridge rule for S3 security log events"
  value       = aws_cloudwatch_event_rule.s3_security_logs.arn
}

# ==============================================================================
# Lambda Function Outputs
# ==============================================================================

output "lambda_security_processor_function_name" {
  description = "Name of the Lambda function for security event processing"
  value       = aws_lambda_function.security_processor.function_name
}

output "lambda_security_processor_function_arn" {
  description = "ARN of the Lambda function for security event processing"
  value       = aws_lambda_function.security_processor.arn
}

output "lambda_security_processor_invoke_arn" {
  description = "ARN to use for invoking the Lambda function"
  value       = aws_lambda_function.security_processor.invoke_arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution.name
}

# ==============================================================================
# CloudWatch Logs Outputs
# ==============================================================================

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# ==============================================================================
# AppFabric Outputs
# ==============================================================================

output "appfabric_app_bundle_arn" {
  description = "ARN of the AppFabric app bundle for SaaS security monitoring"
  value       = aws_appfabric_app_bundle.security_monitoring.arn
}

output "appfabric_service_role_arn" {
  description = "ARN of the IAM role for AppFabric service"
  value       = aws_iam_role.appfabric_service.arn
}

output "appfabric_service_role_name" {
  description = "Name of the IAM role for AppFabric service"
  value       = aws_iam_role.appfabric_service.name
}

# ==============================================================================
# KMS Key Outputs (Conditional)
# ==============================================================================

output "kms_sns_encryption_key_id" {
  description = "ID of the KMS key used for SNS encryption (if enabled)"
  value       = var.enable_sns_encryption ? aws_kms_key.sns_encryption[0].key_id : "SNS encryption disabled"
}

output "kms_sns_encryption_key_arn" {
  description = "ARN of the KMS key used for SNS encryption (if enabled)"
  value       = var.enable_sns_encryption ? aws_kms_key.sns_encryption[0].arn : "SNS encryption disabled"
}

output "kms_sns_encryption_alias_name" {
  description = "Alias name of the KMS key used for SNS encryption (if enabled)"
  value       = var.enable_sns_encryption ? aws_kms_alias.sns_encryption[0].name : "SNS encryption disabled"
}

# ==============================================================================
# Configuration Summary Outputs
# ==============================================================================

output "security_monitoring_configuration" {
  description = "Summary of the security monitoring configuration"
  value = {
    environment               = var.environment
    project_name             = var.project_name
    aws_region              = var.aws_region
    s3_bucket_name          = aws_s3_bucket.security_logs.bucket
    eventbridge_bus_name    = aws_cloudwatch_event_bus.security_monitoring.name
    lambda_function_name    = aws_lambda_function.security_processor.function_name
    sns_topic_name          = aws_sns_topic.security_alerts.name
    appfabric_bundle_arn    = aws_appfabric_app_bundle.security_monitoring.arn
    s3_encryption_enabled   = var.enable_s3_encryption
    sns_encryption_enabled  = var.enable_sns_encryption
    email_alerts_enabled    = var.alert_email != ""
    lambda_timeout          = var.lambda_timeout
    lambda_memory_size      = var.lambda_memory_size
    log_retention_days      = var.log_retention_days
  }
}

# ==============================================================================
# Deployment Instructions Output
# ==============================================================================

output "post_deployment_instructions" {
  description = "Instructions for completing the setup after Terraform deployment"
  value = <<-EOT
  
  🚀 Centralized SaaS Security Monitoring Infrastructure Deployed Successfully!
  
  📋 NEXT STEPS TO COMPLETE SETUP:
  
  1. CONFIRM EMAIL SUBSCRIPTION (if configured):
     ${var.alert_email != "" ? "- Check your email (${var.alert_email}) and confirm the SNS subscription" : "- No email configured. Add email subscription manually if needed."}
  
  2. CONFIGURE APPFABRIC INTEGRATIONS:
     - Navigate to AWS AppFabric console
     - Select your app bundle: ${aws_appfabric_app_bundle.security_monitoring.arn}
     - Add ingestions for your SaaS applications (Slack, Microsoft 365, Salesforce, etc.)
     - Authorize AppFabric to access your SaaS applications
     - Configure ingestion destinations to use S3 bucket: ${aws_s3_bucket.security_logs.bucket}
  
  3. TEST THE MONITORING PIPELINE:
     - Upload a test security log to S3 bucket: ${aws_s3_bucket.security_logs.bucket}
     - Monitor CloudWatch logs for Lambda function: ${aws_cloudwatch_log_group.lambda_logs.name}
     - Verify alerts are sent to configured destinations
  
  4. CUSTOMIZE THREAT DETECTION:
     - Review Lambda function code for threat detection logic
     - Adjust security alert thresholds based on your requirements
     - Add additional SaaS applications to monitoring as needed
  
  📊 MONITORING RESOURCES:
  - S3 Bucket: ${aws_s3_bucket.security_logs.bucket}
  - EventBridge Bus: ${aws_cloudwatch_event_bus.security_monitoring.name}
  - Lambda Function: ${aws_lambda_function.security_processor.function_name}
  - SNS Topic: ${aws_sns_topic.security_alerts.name}
  - AppFabric Bundle: ${split("/", aws_appfabric_app_bundle.security_monitoring.arn)[1]}
  
  🔐 SECURITY CONSIDERATIONS:
  - All resources are deployed with encryption and security best practices
  - IAM roles follow least-privilege principle
  - S3 bucket has public access blocked
  ${var.enable_sns_encryption ? "- SNS topic is encrypted with KMS" : "- Consider enabling SNS encryption for production"}
  
  📖 For detailed configuration instructions, refer to the original recipe documentation.
  EOT
}

# ==============================================================================
# Resource Identifiers for Integration
# ==============================================================================

output "resource_identifiers" {
  description = "Resource identifiers for external integrations"
  value = {
    # For use in other Terraform configurations or external tools
    s3_bucket_name           = aws_s3_bucket.security_logs.bucket
    sns_topic_arn           = aws_sns_topic.security_alerts.arn
    lambda_function_arn     = aws_lambda_function.security_processor.arn
    eventbridge_bus_name    = aws_cloudwatch_event_bus.security_monitoring.name
    appfabric_bundle_arn    = aws_appfabric_app_bundle.security_monitoring.arn
    lambda_execution_role   = aws_iam_role.lambda_execution.arn
    appfabric_service_role  = aws_iam_role.appfabric_service.arn
    log_group_name          = aws_cloudwatch_log_group.lambda_logs.name
  }
}