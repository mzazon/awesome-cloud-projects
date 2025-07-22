# Output values for the content moderation infrastructure

# S3 Bucket Information
output "content_bucket_name" {
  description = "Name of the S3 bucket for content uploads"
  value       = aws_s3_bucket.content_bucket.bucket
}

output "content_bucket_arn" {
  description = "ARN of the S3 bucket for content uploads"
  value       = aws_s3_bucket.content_bucket.arn
}

output "approved_bucket_name" {
  description = "Name of the S3 bucket for approved content"
  value       = aws_s3_bucket.approved_bucket.bucket
}

output "approved_bucket_arn" {
  description = "ARN of the S3 bucket for approved content"
  value       = aws_s3_bucket.approved_bucket.arn
}

output "rejected_bucket_name" {
  description = "Name of the S3 bucket for rejected content"
  value       = aws_s3_bucket.rejected_bucket.bucket
}

output "rejected_bucket_arn" {
  description = "ARN of the S3 bucket for rejected content"
  value       = aws_s3_bucket.rejected_bucket.arn
}

# Lambda Function Information
output "content_analysis_function_name" {
  description = "Name of the content analysis Lambda function"
  value       = aws_lambda_function.content_analysis.function_name
}

output "content_analysis_function_arn" {
  description = "ARN of the content analysis Lambda function"
  value       = aws_lambda_function.content_analysis.arn
}

output "workflow_handler_function_names" {
  description = "Names of the workflow handler Lambda functions"
  value = {
    for key, function in aws_lambda_function.workflow_handlers : key => function.function_name
  }
}

output "workflow_handler_function_arns" {
  description = "ARNs of the workflow handler Lambda functions"
  value = {
    for key, function in aws_lambda_function.workflow_handlers : key => function.arn
  }
}

# EventBridge Information
output "custom_event_bus_name" {
  description = "Name of the custom EventBridge bus for content moderation"
  value       = aws_cloudwatch_event_bus.moderation_bus.name
}

output "custom_event_bus_arn" {
  description = "ARN of the custom EventBridge bus for content moderation"
  value       = aws_cloudwatch_event_bus.moderation_bus.arn
}

output "eventbridge_rule_names" {
  description = "Names of the EventBridge rules for content routing"
  value = {
    approved = aws_cloudwatch_event_rule.approved_content_rule.name
    rejected = aws_cloudwatch_event_rule.rejected_content_rule.name
    review   = aws_cloudwatch_event_rule.review_content_rule.name
  }
}

output "eventbridge_rule_arns" {
  description = "ARNs of the EventBridge rules for content routing"
  value = {
    approved = aws_cloudwatch_event_rule.approved_content_rule.arn
    rejected = aws_cloudwatch_event_rule.rejected_content_rule.arn
    review   = aws_cloudwatch_event_rule.review_content_rule.arn
  }
}

# SNS Information
output "sns_topic_name" {
  description = "Name of the SNS topic for moderation notifications"
  value       = aws_sns_topic.moderation_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for moderation notifications"
  value       = aws_sns_topic.moderation_notifications.arn
}

# IAM Role Information
output "content_analysis_role_name" {
  description = "Name of the IAM role for content analysis Lambda function"
  value       = aws_iam_role.content_analysis_lambda_role.name
}

output "content_analysis_role_arn" {
  description = "ARN of the IAM role for content analysis Lambda function"
  value       = aws_iam_role.content_analysis_lambda_role.arn
}

output "workflow_role_name" {
  description = "Name of the IAM role for workflow Lambda functions"
  value       = aws_iam_role.workflow_lambda_role.name
}

output "workflow_role_arn" {
  description = "ARN of the IAM role for workflow Lambda functions"
  value       = aws_iam_role.workflow_lambda_role.arn
}

# Bedrock Guardrail Information (conditional)
output "bedrock_guardrail_id" {
  description = "ID of the Bedrock guardrail for content filtering"
  value       = var.enable_bedrock_guardrails ? aws_bedrock_guardrail.content_moderation_guardrail[0].guardrail_id : null
}

output "bedrock_guardrail_arn" {
  description = "ARN of the Bedrock guardrail for content filtering"
  value       = var.enable_bedrock_guardrails ? aws_bedrock_guardrail.content_moderation_guardrail[0].guardrail_arn : null
}

output "bedrock_guardrail_version" {
  description = "Version of the Bedrock guardrail for content filtering"
  value       = var.enable_bedrock_guardrails ? aws_bedrock_guardrail.content_moderation_guardrail[0].version : null
}

# CloudWatch Log Groups
output "content_analysis_log_group_name" {
  description = "Name of the CloudWatch log group for content analysis Lambda"
  value       = aws_cloudwatch_log_group.content_analysis_logs.name
}

output "workflow_log_group_names" {
  description = "Names of the CloudWatch log groups for workflow Lambda functions"
  value = {
    for key, log_group in aws_cloudwatch_log_group.workflow_logs : key => log_group.name
  }
}

# Configuration Information
output "bedrock_model_id" {
  description = "Amazon Bedrock model ID used for content analysis"
  value       = var.bedrock_model_id
}

output "notification_email" {
  description = "Email address configured for SNS notifications"
  value       = var.notification_email
  sensitive   = true
}

# Testing and Validation
output "test_upload_command" {
  description = "AWS CLI command to test content upload"
  value       = "echo 'This is test content for moderation.' > test-content.txt && aws s3 cp test-content.txt s3://${aws_s3_bucket.content_bucket.bucket}/"
}

output "test_bucket_list_command" {
  description = "AWS CLI command to list processed content in buckets"
  value       = "aws s3 ls s3://${aws_s3_bucket.approved_bucket.bucket}/approved/ --recursive && aws s3 ls s3://${aws_s3_bucket.rejected_bucket.bucket}/rejected/ --recursive"
}

output "cloudwatch_logs_command" {
  description = "AWS CLI command to view content analysis Lambda logs"
  value       = "aws logs describe-log-streams --log-group-name '${aws_cloudwatch_log_group.content_analysis_logs.name}' --order-by LastEventTime --descending"
}

# Security and Compliance Information
output "s3_encryption_status" {
  description = "Status of S3 bucket encryption configuration"
  value       = var.s3_encryption_enabled ? "Enabled (AES256)" : "Disabled"
}

output "s3_versioning_status" {
  description = "Status of S3 bucket versioning configuration"
  value       = var.s3_versioning_enabled ? "Enabled" : "Disabled"
}

output "guardrails_status" {
  description = "Status of Bedrock Guardrails configuration"
  value       = var.enable_bedrock_guardrails ? "Enabled" : "Disabled"
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources for content moderation system"
  value = {
    s3_buckets = {
      content  = aws_s3_bucket.content_bucket.bucket
      approved = aws_s3_bucket.approved_bucket.bucket
      rejected = aws_s3_bucket.rejected_bucket.bucket
    }
    lambda_functions = {
      content_analysis = aws_lambda_function.content_analysis.function_name
      workflow_handlers = {
        for key, function in aws_lambda_function.workflow_handlers : key => function.function_name
      }
    }
    eventbridge = {
      custom_bus = aws_cloudwatch_event_bus.moderation_bus.name
      rules = {
        approved = aws_cloudwatch_event_rule.approved_content_rule.name
        rejected = aws_cloudwatch_event_rule.rejected_content_rule.name
        review   = aws_cloudwatch_event_rule.review_content_rule.name
      }
    }
    notifications = {
      sns_topic = aws_sns_topic.moderation_notifications.name
      email     = var.notification_email
    }
    security = {
      guardrails_enabled = var.enable_bedrock_guardrails
      encryption_enabled = var.s3_encryption_enabled
      versioning_enabled = var.s3_versioning_enabled
    }
  }
}