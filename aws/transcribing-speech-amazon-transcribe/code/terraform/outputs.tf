# Outputs for Amazon Transcribe Speech Recognition Infrastructure

# ============================================================================
# STORAGE OUTPUTS
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for audio files and transcription outputs"
  value       = aws_s3_bucket.transcribe_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for audio files and transcription outputs"
  value       = aws_s3_bucket.transcribe_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.transcribe_bucket.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.transcribe_bucket.bucket_regional_domain_name
}

output "audio_input_prefix" {
  description = "S3 prefix for audio input files"
  value       = "audio-input/"
}

output "transcription_output_prefix" {
  description = "S3 prefix for transcription output files"
  value       = "transcription-output/"
}

output "custom_vocabulary_prefix" {
  description = "S3 prefix for custom vocabulary files"
  value       = "custom-vocabulary/"
}

output "training_data_prefix" {
  description = "S3 prefix for training data files"
  value       = "training-data/"
}

# ============================================================================
# AMAZON TRANSCRIBE OUTPUTS
# ============================================================================

output "custom_vocabulary_name" {
  description = "Name of the custom vocabulary"
  value       = aws_transcribe_vocabulary.custom_vocabulary.vocabulary_name
}

output "custom_vocabulary_arn" {
  description = "ARN of the custom vocabulary"
  value       = aws_transcribe_vocabulary.custom_vocabulary.arn
}

output "vocabulary_filter_name" {
  description = "Name of the vocabulary filter"
  value       = aws_transcribe_vocabulary_filter.vocabulary_filter.vocabulary_filter_name
}

output "vocabulary_filter_arn" {
  description = "ARN of the vocabulary filter"
  value       = aws_transcribe_vocabulary_filter.vocabulary_filter.arn
}

output "custom_language_model_name" {
  description = "Name of the custom language model"
  value       = aws_transcribe_language_model.custom_language_model.model_name
}

output "custom_language_model_arn" {
  description = "ARN of the custom language model"
  value       = aws_transcribe_language_model.custom_language_model.arn
}

output "language_code" {
  description = "Language code used for transcription"
  value       = var.language_code
}

output "media_format" {
  description = "Default media format for transcription jobs"
  value       = var.media_format
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for transcription processing"
  value       = aws_lambda_function.transcribe_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for transcription processing"
  value       = aws_lambda_function.transcribe_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function for transcription processing"
  value       = aws_lambda_function.transcribe_processor.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function for transcription processing"
  value       = aws_lambda_function.transcribe_processor.qualified_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.transcribe_processor.version
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "transcribe_service_role_name" {
  description = "Name of the IAM role for Transcribe service"
  value       = aws_iam_role.transcribe_service_role.name
}

output "transcribe_service_role_arn" {
  description = "ARN of the IAM role for Transcribe service"
  value       = aws_iam_role.transcribe_service_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "lambda_error_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_error_alarm.alarm_name
}

output "lambda_error_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_error_alarm.arn
}

output "lambda_duration_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration_alarm.alarm_name
}

output "lambda_duration_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration_alarm.arn
}

# ============================================================================
# CONFIGURATION OUTPUTS
# ============================================================================

output "max_speaker_labels" {
  description = "Maximum number of speaker labels for diarization"
  value       = var.max_speaker_labels
}

output "vocabulary_filter_method" {
  description = "Method used for vocabulary filtering"
  value       = var.vocabulary_filter_method
}

output "enable_content_redaction" {
  description = "Whether PII content redaction is enabled"
  value       = var.enable_content_redaction
}

output "redaction_output_type" {
  description = "Type of redaction output"
  value       = var.redaction_output_type
}

output "enable_channel_identification" {
  description = "Whether channel identification is enabled"
  value       = var.enable_channel_identification
}

output "enable_speaker_labels" {
  description = "Whether speaker labels (diarization) are enabled"
  value       = var.enable_speaker_labels
}

output "partial_results_stability" {
  description = "Partial results stability level for streaming"
  value       = var.partial_results_stability
}

output "media_sample_rate_hertz" {
  description = "Media sample rate in Hz for streaming transcription"
  value       = var.media_sample_rate_hertz
}

# ============================================================================
# DEPLOYMENT INFORMATION
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.suffix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# ============================================================================
# USAGE EXAMPLES
# ============================================================================

output "cli_examples" {
  description = "CLI examples for using the transcription infrastructure"
  value = {
    upload_audio_file = "aws s3 cp your-audio-file.mp3 s3://${aws_s3_bucket.transcribe_bucket.id}/audio-input/"
    
    start_transcription_job = "aws transcribe start-transcription-job --transcription-job-name my-job --language-code ${var.language_code} --media-format ${var.media_format} --media MediaFileUri=s3://${aws_s3_bucket.transcribe_bucket.id}/audio-input/your-audio-file.mp3 --output-bucket-name ${aws_s3_bucket.transcribe_bucket.id} --output-key transcription-output/my-job.json"
    
    check_job_status = "aws transcribe get-transcription-job --transcription-job-name my-job"
    
    invoke_lambda_function = "aws lambda invoke --function-name ${aws_lambda_function.transcribe_processor.function_name} --payload '{\"jobName\":\"my-job\"}' response.json"
    
    list_vocabularies = "aws transcribe list-vocabularies"
    
    list_transcription_jobs = "aws transcribe list-transcription-jobs"
    
    download_transcript = "aws s3 cp s3://${aws_s3_bucket.transcribe_bucket.id}/transcription-output/my-job.json ./transcript.json"
  }
}

output "streaming_transcription_config" {
  description = "Configuration for streaming transcription"
  value = {
    language_code = var.language_code
    media_sample_rate_hertz = var.media_sample_rate_hertz
    media_encoding = "pcm"
    enable_partial_results_stabilization = var.enable_partial_results_stabilization
    partial_results_stability = var.partial_results_stability
    vocabulary_name = aws_transcribe_vocabulary.custom_vocabulary.vocabulary_name
    show_speaker_labels = var.enable_speaker_labels
  }
}

output "transcription_job_settings" {
  description = "Recommended settings for transcription jobs"
  value = {
    vocabulary_name = aws_transcribe_vocabulary.custom_vocabulary.vocabulary_name
    vocabulary_filter_name = aws_transcribe_vocabulary_filter.vocabulary_filter.vocabulary_filter_name
    vocabulary_filter_method = var.vocabulary_filter_method
    show_speaker_labels = var.enable_speaker_labels
    max_speaker_labels = var.max_speaker_labels
    channel_identification = var.enable_channel_identification
    content_redaction = var.enable_content_redaction ? {
      redaction_type = "PII"
      redaction_output = var.redaction_output_type
    } : null
  }
}

# ============================================================================
# TROUBLESHOOTING OUTPUTS
# ============================================================================

output "troubleshooting_info" {
  description = "Information for troubleshooting transcription issues"
  value = {
    supported_audio_formats = ["mp3", "mp4", "wav", "flac", "amr", "ogg", "webm"]
    supported_sample_rates = [8000, 16000, 22050, 44100, 48000]
    max_audio_file_size = "2GB"
    max_audio_duration = "4 hours"
    supported_languages = ["en-US", "en-GB", "es-US", "es-ES", "fr-CA", "fr-FR", "de-DE", "it-IT", "pt-BR", "ja-JP", "ko-KR", "zh-CN"]
    cloudwatch_logs_group = aws_cloudwatch_log_group.lambda_logs.name
    error_alarm = aws_cloudwatch_metric_alarm.lambda_error_alarm.alarm_name
    duration_alarm = aws_cloudwatch_metric_alarm.lambda_duration_alarm.alarm_name
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    standard_transcription_cost = "$0.024 per minute"
    streaming_transcription_cost = "$0.025 per minute"
    custom_vocabulary_cost = "Free"
    custom_language_model_cost = "$1.60 per hour of training"
    pii_redaction_cost = "Additional $0.006 per minute"
    s3_storage_cost = "Based on storage class and region"
    lambda_cost = "Based on execution time and memory"
    lifecycle_policy_enabled = var.s3_lifecycle_enabled
    transition_to_ia_days = var.s3_transition_to_ia_days
    transition_to_glacier_days = var.s3_transition_to_glacier_days
  }
}

# ============================================================================
# NEXT STEPS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    test_infrastructure = "Upload a sample audio file to s3://${aws_s3_bucket.transcribe_bucket.id}/audio-input/ and verify transcription job starts automatically"
    
    customize_vocabulary = "Add domain-specific terms to the custom vocabulary by updating the vocabulary_terms variable"
    
    monitor_performance = "Review CloudWatch metrics and logs for Lambda function performance and transcription job success rates"
    
    implement_streaming = "Set up WebSocket client for real-time streaming transcription using the provided configuration"
    
    integrate_downstream = "Connect transcription results to downstream applications like databases, analytics platforms, or notification systems"
    
    scale_for_production = "Review and adjust Lambda memory, timeout, and concurrency settings based on production workload"
    
    enhance_security = "Implement additional security measures like VPC endpoints, encryption keys, and access controls"
    
    optimize_costs = "Monitor usage patterns and adjust S3 lifecycle policies and resource configurations for cost optimization"
  }
}

# ============================================================================
# DOCUMENTATION LINKS
# ============================================================================

output "documentation_links" {
  description = "Useful documentation links"
  value = {
    amazon_transcribe_docs = "https://docs.aws.amazon.com/transcribe/"
    api_reference = "https://docs.aws.amazon.com/transcribe/latest/APIReference/"
    streaming_api_docs = "https://docs.aws.amazon.com/transcribe/latest/dg/streaming.html"
    custom_vocabulary_docs = "https://docs.aws.amazon.com/transcribe/latest/dg/custom-vocabulary.html"
    language_models_docs = "https://docs.aws.amazon.com/transcribe/latest/dg/custom-language-models.html"
    pricing_info = "https://aws.amazon.com/transcribe/pricing/"
    best_practices = "https://docs.aws.amazon.com/transcribe/latest/dg/best-practices.html"
    troubleshooting = "https://docs.aws.amazon.com/transcribe/latest/dg/troubleshooting.html"
  }
}