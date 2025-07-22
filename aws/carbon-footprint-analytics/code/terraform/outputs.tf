# Outputs for AWS Sustainability Intelligence Dashboard
# Provides important resource information and configuration details

# ============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ============================================================================

output "project_name" {
  description = "Name of the sustainability analytics project"
  value       = var.project_name
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# STORAGE AND DATA LAKE OUTPUTS
# ============================================================================

output "s3_data_lake_bucket_name" {
  description = "Name of the S3 bucket used for sustainability data lake"
  value       = aws_s3_bucket.sustainability_data_lake.bucket
}

output "s3_data_lake_bucket_arn" {
  description = "ARN of the S3 data lake bucket"
  value       = aws_s3_bucket.sustainability_data_lake.arn
}

output "s3_data_lake_bucket_domain_name" {
  description = "Domain name of the S3 data lake bucket"
  value       = aws_s3_bucket.sustainability_data_lake.bucket_domain_name
}

output "s3_quicksight_manifest_uri" {
  description = "S3 URI of the QuickSight manifest file"
  value       = "s3://${aws_s3_bucket.sustainability_data_lake.bucket}/${aws_s3_object.quicksight_manifest.key}"
}

# ============================================================================
# SECURITY AND ENCRYPTION OUTPUTS
# ============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for sustainability data encryption"
  value       = aws_kms_key.sustainability_key.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for sustainability data encryption"
  value       = aws_kms_key.sustainability_key.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for sustainability data encryption"
  value       = aws_kms_alias.sustainability_key_alias.name
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for sustainability data processing"
  value       = aws_lambda_function.sustainability_data_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for sustainability data processing"
  value       = aws_lambda_function.sustainability_data_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.sustainability_data_processor.invoke_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.sustainability_data_processor.version
}

output "lambda_function_runtime" {
  description = "Runtime version of the Lambda function"
  value       = aws_lambda_function.sustainability_data_processor.runtime
}

output "lambda_function_architecture" {
  description = "Architecture of the Lambda function (optimized for sustainability)"
  value       = aws_lambda_function.sustainability_data_processor.architectures[0]
}

output "lambda_cloudwatch_log_group" {
  description = "CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ============================================================================
# IAM ROLE AND POLICY OUTPUTS
# ============================================================================

output "lambda_execution_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "sustainability_analytics_policy_arn" {
  description = "ARN of the custom IAM policy for sustainability analytics"
  value       = aws_iam_policy.sustainability_analytics_policy.arn
}

# ============================================================================
# AUTOMATION AND SCHEDULING OUTPUTS
# ============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled data processing"
  value       = aws_cloudwatch_event_rule.sustainability_data_processing.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled data processing"
  value       = aws_cloudwatch_event_rule.sustainability_data_processing.arn
}

output "eventbridge_schedule_expression" {
  description = "Schedule expression for automated data processing"
  value       = aws_cloudwatch_event_rule.sustainability_data_processing.schedule_expression
}

# ============================================================================
# MONITORING AND ALERTING OUTPUTS
# ============================================================================

output "sns_topic_name" {
  description = "Name of the SNS topic for sustainability alerts"
  value       = aws_sns_topic.sustainability_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for sustainability alerts"
  value       = aws_sns_topic.sustainability_alerts.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch operational dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.sustainability_dashboard.dashboard_name}"
}

output "lambda_error_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_error_alarm.alarm_name
}

output "lambda_duration_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration_alarm.alarm_name
}

output "data_processing_success_alarm_name" {
  description = "Name of the CloudWatch alarm for data processing success monitoring"
  value       = var.enable_enhanced_monitoring ? aws_cloudwatch_metric_alarm.data_processing_success_alarm[0].alarm_name : null
}

# ============================================================================
# ERROR HANDLING OUTPUTS
# ============================================================================

output "dead_letter_queue_name" {
  description = "Name of the SQS dead letter queue for Lambda failures"
  value       = aws_sqs_queue.lambda_dlq.name
}

output "dead_letter_queue_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = aws_sqs_queue.lambda_dlq.arn
}

output "dead_letter_queue_url" {
  description = "URL of the SQS dead letter queue"
  value       = aws_sqs_queue.lambda_dlq.url
}

# ============================================================================
# QUICKSIGHT OUTPUTS
# ============================================================================

output "quicksight_data_source_id" {
  description = "ID of the QuickSight data source"
  value       = aws_quicksight_data_source.sustainability_data_source.data_source_id
}

output "quicksight_data_source_arn" {
  description = "ARN of the QuickSight data source"
  value       = aws_quicksight_data_source.sustainability_data_source.arn
}

output "quicksight_console_url" {
  description = "URL to access QuickSight console for dashboard creation"
  value       = "https://${data.aws_region.current.name}.quicksight.aws.amazon.com/"
}

# ============================================================================
# COST AND SUSTAINABILITY INFORMATION
# ============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for sustainability analytics infrastructure"
  value = {
    lambda_invocations = "~$1-5 (based on 1000 monthly invocations)"
    s3_storage        = "~$1-10 (based on 10GB sustainability data)"
    cloudwatch_logs   = "~$0.50-2 (based on log volume)"
    sns_notifications = "~$0.50-2 (based on alert frequency)"
    quicksight_user   = "$18/user/month (QuickSight Standard)"
    total_estimated   = "~$21-37/month (excluding QuickSight users)"
  }
}

output "sustainability_optimization_notes" {
  description = "Sustainability optimization features enabled"
  value = {
    lambda_architecture     = "ARM64 (Graviton) for better energy efficiency"
    s3_lifecycle_policy    = "Automated transition to cheaper, more efficient storage classes"
    kms_key_rotation       = var.kms_key_rotation ? "Enabled" : "Disabled"
    resource_right_sizing  = "Lambda memory optimized for cost and carbon efficiency"
    monitoring_enabled     = "CloudWatch metrics for optimization opportunities"
  }
}

# ============================================================================
# NEXT STEPS AND CONFIGURATION GUIDANCE
# ============================================================================

output "quicksight_setup_instructions" {
  description = "Instructions for completing QuickSight dashboard setup"
  value = {
    step_1 = "Navigate to QuickSight Console: https://${data.aws_region.current.name}.quicksight.aws.amazon.com/"
    step_2 = "Sign up for QuickSight Standard edition if not already configured"
    step_3 = "Grant S3 access permissions to bucket: ${aws_s3_bucket.sustainability_data_lake.bucket}"
    step_4 = "Create dataset using data source: ${aws_quicksight_data_source.sustainability_data_source.name}"
    step_5 = "Build dashboard with carbon footprint and cost correlation visualizations"
    step_6 = "Configure scheduled refresh to align with monthly carbon footprint data availability"
  }
}

output "manual_lambda_trigger_command" {
  description = "AWS CLI command to manually trigger the sustainability data processing function"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.sustainability_data_processor.function_name} --payload '{\"trigger_source\":\"manual\",\"environment\":\"${var.environment}\"}' response.json"
}

output "s3_data_locations" {
  description = "S3 bucket locations for different types of sustainability data"
  value = {
    raw_data              = "s3://${aws_s3_bucket.sustainability_data_lake.bucket}/raw-data/"
    processed_analytics   = "s3://${aws_s3_bucket.sustainability_data_lake.bucket}/sustainability-analytics/"
    quicksight_manifests  = "s3://${aws_s3_bucket.sustainability_data_lake.bucket}/manifests/"
    cost_explorer_exports = "s3://${aws_s3_bucket.sustainability_data_lake.bucket}/cost-data/"
  }
}

output "carbon_footprint_data_access" {
  description = "Information about accessing AWS Customer Carbon Footprint Tool data"
  value = {
    tool_location     = "AWS Billing Console > Carbon Footprint Tool"
    data_availability = "Monthly data with 3-month delay"
    api_access        = "Use AWS Data Exports for programmatic access (when available)"
    manual_export     = "Download CSV files manually for immediate analysis"
    data_scope        = "Scope 2 emissions (electricity consumption for compute services)"
  }
}

# ============================================================================
# TERRAFORM STATE AND RESOURCE MANAGEMENT
# ============================================================================

output "terraform_workspace" {
  description = "Current Terraform workspace"
  value       = terraform.workspace
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value = {
    Project     = "SustainabilityIntelligence"
    Environment = var.environment
    Purpose     = "Carbon footprint analytics and cost optimization"
    CreatedBy   = "Terraform"
    Recipe      = "intelligent-sustainability-dashboards-aws-sustainability-hub-quicksight"
  }
}