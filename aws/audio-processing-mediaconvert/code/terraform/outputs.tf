# Outputs for Audio Processing Pipeline
# This file defines the outputs that will be displayed after successful deployment

# =============================================================================
# S3 Bucket Outputs
# =============================================================================

output "input_bucket_name" {
  description = "Name of the S3 input bucket for audio files"
  value       = aws_s3_bucket.input.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 input bucket"
  value       = aws_s3_bucket.input.arn
}

output "output_bucket_name" {
  description = "Name of the S3 output bucket for processed audio files"
  value       = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 output bucket"
  value       = aws_s3_bucket.output.arn
}

output "access_logs_bucket_name" {
  description = "Name of the S3 access logs bucket (if enabled)"
  value       = var.enable_s3_access_logging ? aws_s3_bucket.access_logs[0].bucket : null
}

# =============================================================================
# Lambda Function Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function that processes audio files"
  value       = aws_lambda_function.audio_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.audio_processor.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda.name
}

# =============================================================================
# MediaConvert Outputs
# =============================================================================

output "mediaconvert_endpoint" {
  description = "MediaConvert endpoint URL for the current region"
  value       = data.aws_mediaconvert_endpoint.current.endpoint_url
}

output "mediaconvert_role_arn" {
  description = "ARN of the IAM role used by MediaConvert"
  value       = aws_iam_role.mediaconvert.arn
}

output "mediaconvert_job_template_arn" {
  description = "ARN of the MediaConvert job template"
  value       = aws_media_convert_job_template.audio_processing.arn
}

output "mediaconvert_job_template_name" {
  description = "Name of the MediaConvert job template"
  value       = aws_media_convert_job_template.audio_processing.name
}

output "mediaconvert_preset_arn" {
  description = "ARN of the MediaConvert audio preset"
  value       = aws_media_convert_preset.enhanced_audio.arn
}

output "mediaconvert_preset_name" {
  description = "Name of the MediaConvert audio preset"
  value       = aws_media_convert_preset.enhanced_audio.name
}

# =============================================================================
# SNS Topic Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for processing notifications"
  value       = aws_sns_topic.notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.notifications.name
}

# =============================================================================
# CloudWatch Dashboard Outputs
# =============================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.audio_pipeline.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.audio_pipeline.dashboard_name}"
}

# =============================================================================
# Security Outputs
# =============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for S3 encryption (if enabled)"
  value       = var.s3_encryption_enabled ? aws_kms_key.s3_encryption[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for S3 encryption (if enabled)"
  value       = var.s3_encryption_enabled ? aws_kms_key.s3_encryption[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for S3 encryption (if enabled)"
  value       = var.s3_encryption_enabled ? aws_kms_alias.s3_encryption[0].name : null
}

# =============================================================================
# Configuration Outputs
# =============================================================================

output "supported_audio_formats" {
  description = "List of supported audio file formats"
  value       = var.supported_audio_extensions
}

output "audio_processing_settings" {
  description = "Audio processing configuration settings"
  value = {
    mp3_bitrate     = var.audio_bitrate_mp3
    aac_bitrate     = var.audio_bitrate_aac
    sample_rate     = var.audio_sample_rate
    channels        = var.audio_channels
    loudness_target = var.loudness_target_lkfs
  }
}

# =============================================================================
# Usage Instructions
# =============================================================================

output "usage_instructions" {
  description = "Instructions for using the audio processing pipeline"
  value = {
    upload_command = "aws s3 cp your-audio-file.mp3 s3://${aws_s3_bucket.input.bucket}/"
    monitor_logs   = "aws logs tail ${aws_cloudwatch_log_group.lambda.name} --follow"
    list_jobs      = "aws mediaconvert list-jobs --endpoint-url ${data.aws_mediaconvert_endpoint.current.endpoint_url}"
    output_formats = {
      mp3  = "s3://${aws_s3_bucket.output.bucket}/mp3/"
      aac  = "s3://${aws_s3_bucket.output.bucket}/aac/"
      flac = "s3://${aws_s3_bucket.output.bucket}/flac/"
    }
  }
}

# =============================================================================
# Cost Estimation
# =============================================================================

output "estimated_costs" {
  description = "Estimated costs for using the audio processing pipeline"
  value = {
    notice = "Costs depend on usage patterns and file sizes"
    components = {
      s3_storage        = "~$0.023 per GB per month"
      lambda_invocations = "~$0.0000002 per invocation"
      mediaconvert      = "~$0.0075 per minute of audio processed"
      cloudwatch_logs   = "~$0.50 per GB ingested"
      sns_notifications = "~$0.50 per million notifications"
    }
    optimization_tips = [
      "Use S3 lifecycle policies to transition old files to cheaper storage classes",
      "Monitor MediaConvert job durations to optimize settings",
      "Set appropriate CloudWatch log retention periods",
      "Use SNS filtering to reduce notification costs"
    ]
  }
}

# =============================================================================
# Troubleshooting Information
# =============================================================================

output "troubleshooting_commands" {
  description = "Commands for troubleshooting the audio processing pipeline"
  value = {
    check_lambda_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda.name} --order-by LastEventTime --descending"
    test_s3_event     = "aws s3 cp test-file.mp3 s3://${aws_s3_bucket.input.bucket}/test-file.mp3"
    check_mediaconvert_jobs = "aws mediaconvert list-jobs --endpoint-url ${data.aws_mediaconvert_endpoint.current.endpoint_url} --max-results 10"
    verify_permissions = "aws iam get-role --role-name ${aws_iam_role.mediaconvert.name}"
  }
}