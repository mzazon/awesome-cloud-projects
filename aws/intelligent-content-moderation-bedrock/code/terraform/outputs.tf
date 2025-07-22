# =====================================================
# OUTPUT VALUES
# =====================================================

output "content_bucket_name" {
  description = "Name of the S3 bucket for content uploads"
  value       = aws_s3_bucket.content_bucket.id
}

output "content_bucket_arn" {
  description = "ARN of the S3 bucket for content uploads"
  value       = aws_s3_bucket.content_bucket.arn
}

output "approved_bucket_name" {
  description = "Name of the S3 bucket for approved content"
  value       = aws_s3_bucket.approved_bucket.id
}

output "approved_bucket_arn" {
  description = "ARN of the S3 bucket for approved content"
  value       = aws_s3_bucket.approved_bucket.arn
}

output "rejected_bucket_name" {
  description = "Name of the S3 bucket for rejected content"
  value       = aws_s3_bucket.rejected_bucket.id
}

output "rejected_bucket_arn" {
  description = "ARN of the S3 bucket for rejected content"
  value       = aws_s3_bucket.rejected_bucket.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.moderation_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.moderation_notifications.name
}

output "eventbridge_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.content_moderation_bus.name
}

output "eventbridge_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.content_moderation_bus.arn
}

output "content_analysis_function_name" {
  description = "Name of the content analysis Lambda function"
  value       = aws_lambda_function.content_analysis_function.function_name
}

output "content_analysis_function_arn" {
  description = "ARN of the content analysis Lambda function"
  value       = aws_lambda_function.content_analysis_function.arn
}

output "workflow_function_names" {
  description = "Names of the workflow Lambda functions"
  value = {
    for k, v in aws_lambda_function.workflow_functions : k => v.function_name
  }
}

output "workflow_function_arns" {
  description = "ARNs of the workflow Lambda functions"
  value = {
    for k, v in aws_lambda_function.workflow_functions : k => v.arn
  }
}

output "bedrock_guardrail_id" {
  description = "ID of the Bedrock guardrail (if enabled)"
  value       = var.enable_guardrails ? aws_bedrock_guardrail.content_moderation_guardrail[0].guardrail_id : null
}

output "bedrock_guardrail_arn" {
  description = "ARN of the Bedrock guardrail (if enabled)"
  value       = var.enable_guardrails ? aws_bedrock_guardrail.content_moderation_guardrail[0].guardrail_arn : null
}

output "iam_role_name" {
  description = "Name of the IAM role for Lambda functions"
  value       = aws_iam_role.content_analysis_lambda_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Lambda functions"
  value       = aws_iam_role.content_analysis_lambda_role.arn
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = merge(
    { content_analysis = aws_cloudwatch_log_group.content_analysis_logs.name },
    { for k, v in aws_cloudwatch_log_group.workflow_logs : k => v.name }
  )
}

output "eventbridge_rules" {
  description = "EventBridge rules for workflow routing"
  value = {
    for k, v in aws_cloudwatch_event_rule.content_workflow_rules : k => {
      name = v.name
      arn  = v.arn
    }
  }
}

# =====================================================
# TESTING AND VALIDATION OUTPUTS
# =====================================================

output "test_commands" {
  description = "Commands to test the content moderation system"
  value = {
    upload_test_content = "aws s3 cp test-content.txt s3://${aws_s3_bucket.content_bucket.id}/"
    list_approved_content = "aws s3 ls s3://${aws_s3_bucket.approved_bucket.id}/approved/ --recursive"
    list_rejected_content = "aws s3 ls s3://${aws_s3_bucket.rejected_bucket.id}/rejected/ --recursive"
    check_logs = "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${aws_lambda_function.content_analysis_function.function_name}'"
  }
}

output "monitoring_urls" {
  description = "AWS Console URLs for monitoring the system"
  value = {
    content_analysis_logs = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#logsV2:log-groups/log-group/%2Faws%2Flambda%2F${aws_lambda_function.content_analysis_function.function_name}"
    eventbridge_bus = "https://${local.region}.console.aws.amazon.com/events/home?region=${local.region}#/eventbus/${aws_cloudwatch_event_bus.content_moderation_bus.name}"
    sns_topic = "https://${local.region}.console.aws.amazon.com/sns/v3/home?region=${local.region}#/topic/${aws_sns_topic.moderation_notifications.arn}"
    s3_buckets = "https://s3.console.aws.amazon.com/s3/buckets?region=${local.region}"
  }
}

# =====================================================
# CONFIGURATION SUMMARY
# =====================================================

output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    project_name                = var.project_name
    environment                 = var.environment
    aws_region                  = local.region
    bedrock_model_id           = var.bedrock_model_id
    notification_email         = var.notification_email
    guardrails_enabled         = var.enable_guardrails
    s3_versioning_enabled      = var.enable_s3_versioning
    s3_expiration_days         = var.s3_object_expiration_days
    content_analysis_memory_mb = var.content_analysis_memory_size
    workflow_memory_mb         = var.workflow_memory_size
    lambda_timeout_seconds     = var.lambda_timeout
  }
}

# =====================================================
# RESOURCE COUNTS
# =====================================================

output "resource_counts" {
  description = "Count of deployed resources by type"
  value = {
    s3_buckets           = 3
    lambda_functions     = 4
    iam_roles           = 1
    sns_topics          = 1
    eventbridge_buses   = 1
    eventbridge_rules   = 3
    cloudwatch_log_groups = 4
    bedrock_guardrails  = var.enable_guardrails ? 1 : 0
  }
}