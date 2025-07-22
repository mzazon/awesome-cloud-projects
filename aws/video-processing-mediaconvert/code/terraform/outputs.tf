# Output Values for Video Processing Workflow
# Provides important resource information for verification and integration

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "s3_source_bucket_name" {
  description = "Name of the S3 bucket for source video files"
  value       = aws_s3_bucket.source.bucket
}

output "s3_source_bucket_arn" {
  description = "ARN of the S3 bucket for source video files"
  value       = aws_s3_bucket.source.arn
}

output "s3_output_bucket_name" {
  description = "Name of the S3 bucket for processed video files"
  value       = aws_s3_bucket.output.bucket
}

output "s3_output_bucket_arn" {
  description = "ARN of the S3 bucket for processed video files"
  value       = aws_s3_bucket.output.arn
}

output "s3_source_bucket_url" {
  description = "URL of the S3 source bucket"
  value       = "https://${aws_s3_bucket.source.bucket}.s3.${data.aws_region.current.name}.amazonaws.com"
}

output "s3_output_bucket_url" {
  description = "URL of the S3 output bucket"
  value       = "https://${aws_s3_bucket.output.bucket}.s3.${data.aws_region.current.name}.amazonaws.com"
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the video processing Lambda function"
  value       = aws_lambda_function.video_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the video processing Lambda function"
  value       = aws_lambda_function.video_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the video processing Lambda function"
  value       = aws_lambda_function.video_processor.invoke_arn
}

output "completion_handler_function_name" {
  description = "Name of the completion handler Lambda function"
  value       = var.enable_completion_handler ? aws_lambda_function.completion_handler[0].function_name : null
}

output "completion_handler_function_arn" {
  description = "ARN of the completion handler Lambda function"
  value       = var.enable_completion_handler ? aws_lambda_function.completion_handler[0].arn : null
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "mediaconvert_role_name" {
  description = "Name of the MediaConvert IAM role"
  value       = aws_iam_role.mediaconvert_role.name
}

output "mediaconvert_role_arn" {
  description = "ARN of the MediaConvert IAM role"
  value       = aws_iam_role.mediaconvert_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}

# ============================================================================
# MEDIACONVERT OUTPUTS
# ============================================================================

output "mediaconvert_endpoint" {
  description = "MediaConvert endpoint URL for the current region"
  value       = local.mediaconvert_endpoint
}

output "mediaconvert_job_settings" {
  description = "MediaConvert job configuration settings"
  value = {
    video_bitrate   = var.mediaconvert_bitrate
    video_framerate = var.mediaconvert_framerate
    video_width     = var.mediaconvert_width
    video_height    = var.mediaconvert_height
  }
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION OUTPUTS
# ============================================================================

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = var.cloudfront_enabled ? aws_cloudfront_distribution.video_distribution[0].id : null
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = var.cloudfront_enabled ? aws_cloudfront_distribution.video_distribution[0].arn : null
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = var.cloudfront_enabled ? aws_cloudfront_distribution.video_distribution[0].domain_name : null
}

output "cloudfront_hosted_zone_id" {
  description = "Hosted zone ID of the CloudFront distribution"
  value       = var.cloudfront_enabled ? aws_cloudfront_distribution.video_distribution[0].hosted_zone_id : null
}

output "cloudfront_distribution_url" {
  description = "Full URL of the CloudFront distribution"
  value       = var.cloudfront_enabled ? "https://${aws_cloudfront_distribution.video_distribution[0].domain_name}" : null
}

# ============================================================================
# EVENTBRIDGE OUTPUTS
# ============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for MediaConvert job completion"
  value       = var.enable_completion_handler ? aws_cloudwatch_event_rule.mediaconvert_completion[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for MediaConvert job completion"
  value       = var.enable_completion_handler ? aws_cloudwatch_event_rule.mediaconvert_completion[0].arn : null
}

# ============================================================================
# CLOUDWATCH LOGS OUTPUTS
# ============================================================================

output "video_processor_log_group_name" {
  description = "Name of the CloudWatch log group for video processor"
  value       = aws_cloudwatch_log_group.video_processor_logs.name
}

output "video_processor_log_group_arn" {
  description = "ARN of the CloudWatch log group for video processor"
  value       = aws_cloudwatch_log_group.video_processor_logs.arn
}

output "completion_handler_log_group_name" {
  description = "Name of the CloudWatch log group for completion handler"
  value       = var.enable_completion_handler ? aws_cloudwatch_log_group.completion_handler_logs[0].name : null
}

output "completion_handler_log_group_arn" {
  description = "ARN of the CloudWatch log group for completion handler"
  value       = var.enable_completion_handler ? aws_cloudwatch_log_group.completion_handler_logs[0].arn : null
}

# ============================================================================
# DEPLOYMENT INFORMATION
# ============================================================================

output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

output "project_name" {
  description = "Project name used for resource tagging"
  value       = var.project_name
}

output "environment" {
  description = "Environment name used for resource tagging"
  value       = var.environment
}

# ============================================================================
# USAGE INSTRUCTIONS
# ============================================================================

output "usage_instructions" {
  description = "Instructions for using the video processing workflow"
  value = {
    upload_command = "aws s3 cp your-video.mp4 s3://${aws_s3_bucket.source.bucket}/"
    list_jobs      = "aws mediaconvert list-jobs --endpoint-url ${local.mediaconvert_endpoint}"
    view_logs      = "aws logs tail /aws/lambda/${aws_lambda_function.video_processor.function_name} --follow"
    output_location = "s3://${aws_s3_bucket.output.bucket}/"
    cloudfront_url  = var.cloudfront_enabled ? "https://${aws_cloudfront_distribution.video_distribution[0].domain_name}" : "CloudFront not enabled"
  }
}

# ============================================================================
# MONITORING URLS
# ============================================================================

output "monitoring_urls" {
  description = "URLs for monitoring the video processing workflow"
  value = {
    lambda_function_console = "https://console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.video_processor.function_name}"
    s3_source_console      = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.source.bucket}"
    s3_output_console      = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.output.bucket}"
    mediaconvert_console   = "https://console.aws.amazon.com/mediaconvert/home?region=${data.aws_region.current.name}#/jobs"
    cloudwatch_logs        = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.video_processor_logs.name, "/", "$252F")}"
    cloudfront_console     = var.cloudfront_enabled ? "https://console.aws.amazon.com/cloudfront/home?region=${data.aws_region.current.name}#/distributions/${aws_cloudfront_distribution.video_distribution[0].id}" : null
  }
}

# ============================================================================
# COST ESTIMATION
# ============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the video processing workflow"
  value = {
    s3_storage_gb_month     = "~$0.023 per GB per month (Standard storage)"
    lambda_invocations      = "~$0.20 per 1M invocations"
    lambda_duration_gb_sec  = "~$0.0000166667 per GB-second"
    mediaconvert_processing = "~$0.0075 per minute of video processed (HD)"
    cloudfront_requests     = var.cloudfront_enabled ? "~$0.0075 per 10,000 requests" : "CloudFront not enabled"
    cloudfront_data_transfer = var.cloudfront_enabled ? "~$0.085 per GB (first 10TB)" : "CloudFront not enabled"
    note = "Actual costs depend on usage patterns and video processing volume"
  }
}

# ============================================================================
# VALIDATION COMMANDS
# ============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    test_upload           = "aws s3 cp test-video.mp4 s3://${aws_s3_bucket.source.bucket}/"
    check_processing      = "aws mediaconvert list-jobs --endpoint-url ${local.mediaconvert_endpoint} --max-results 10"
    list_output_files     = "aws s3 ls s3://${aws_s3_bucket.output.bucket}/ --recursive"
    view_lambda_logs      = "aws logs tail /aws/lambda/${aws_lambda_function.video_processor.function_name} --since 1h"
    test_cloudfront_access = var.cloudfront_enabled ? "curl -I https://${aws_cloudfront_distribution.video_distribution[0].domain_name}/path/to/video.mp4" : "CloudFront not enabled"
  }
}