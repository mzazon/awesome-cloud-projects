# Outputs for multi-language voice processing pipeline infrastructure
# These outputs provide essential information for verifying deployment success and integration

# ============================================================================
# S3 Bucket Outputs
# ============================================================================

output "input_bucket_name" {
  description = "Name of the S3 bucket for input audio files"
  value       = aws_s3_bucket.input.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 bucket for input audio files"
  value       = aws_s3_bucket.input.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for output audio files"
  value       = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for output audio files"
  value       = aws_s3_bucket.output.arn
}

# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "jobs_table_name" {
  description = "Name of the DynamoDB table for job tracking"
  value       = aws_dynamodb_table.jobs.name
}

output "jobs_table_arn" {
  description = "ARN of the DynamoDB table for job tracking"
  value       = aws_dynamodb_table.jobs.arn
}

output "jobs_table_stream_arn" {
  description = "ARN of the DynamoDB table stream (if enabled)"
  value       = aws_dynamodb_table.jobs.stream_arn
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "language_detector_function_name" {
  description = "Name of the language detector Lambda function"
  value       = aws_lambda_function.language_detector.function_name
}

output "language_detector_function_arn" {
  description = "ARN of the language detector Lambda function"
  value       = aws_lambda_function.language_detector.arn
}

output "transcription_processor_function_name" {
  description = "Name of the transcription processor Lambda function"
  value       = aws_lambda_function.transcription_processor.function_name
}

output "transcription_processor_function_arn" {
  description = "ARN of the transcription processor Lambda function"
  value       = aws_lambda_function.transcription_processor.arn
}

output "translation_processor_function_name" {
  description = "Name of the translation processor Lambda function"
  value       = aws_lambda_function.translation_processor.function_name
}

output "translation_processor_function_arn" {
  description = "ARN of the translation processor Lambda function"
  value       = aws_lambda_function.translation_processor.arn
}

output "speech_synthesizer_function_name" {
  description = "Name of the speech synthesizer Lambda function"
  value       = aws_lambda_function.speech_synthesizer.function_name
}

output "speech_synthesizer_function_arn" {
  description = "ARN of the speech synthesizer Lambda function"
  value       = aws_lambda_function.speech_synthesizer.arn
}

output "job_status_checker_function_name" {
  description = "Name of the job status checker Lambda function"
  value       = aws_lambda_function.job_status_checker.function_name
}

output "job_status_checker_function_arn" {
  description = "ARN of the job status checker Lambda function"
  value       = aws_lambda_function.job_status_checker.arn
}

# ============================================================================
# Step Functions Outputs
# ============================================================================

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.voice_processing.name
}

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.voice_processing.arn
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions_role.arn
}

# ============================================================================
# API Gateway Outputs (Optional)
# ============================================================================

output "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.voice_processing[0].id : null
}

output "api_gateway_rest_api_arn" {
  description = "ARN of the API Gateway REST API"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.voice_processing[0].arn : null
}

output "api_gateway_stage_arn" {
  description = "ARN of the API Gateway stage"
  value       = var.enable_api_gateway ? aws_api_gateway_stage.voice_processing[0].arn : null
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the API Gateway stage"
  value       = var.enable_api_gateway ? aws_api_gateway_stage.voice_processing[0].invoke_url : null
}

# ============================================================================
# SNS and SQS Outputs
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.notifications[0].arn : null
}

output "processing_queue_url" {
  description = "URL of the SQS processing queue"
  value       = aws_sqs_queue.processing.url
}

output "processing_queue_arn" {
  description = "ARN of the SQS processing queue"
  value       = aws_sqs_queue.processing.arn
}

output "dead_letter_queue_url" {
  description = "URL of the SQS dead letter queue"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].url : null
}

output "dead_letter_queue_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].arn : null
}

# ============================================================================
# IAM Role Outputs
# ============================================================================

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "cloudwatch_log_group_names" {
  description = "Names of CloudWatch log groups for Lambda functions"
  value = {
    for key, log_group in aws_cloudwatch_log_group.lambda_logs : key => log_group.name
  }
}

output "step_functions_log_group_name" {
  description = "Name of CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.step_functions.name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = var.enable_detailed_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.voice_processing[0].dashboard_name}" : null
}

# ============================================================================
# KMS Key Outputs
# ============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.voice_processing[0].id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.voice_processing[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_alias.voice_processing[0].name : null
}

# ============================================================================
# Configuration Outputs
# ============================================================================

output "configured_target_languages" {
  description = "List of configured target languages for translation"
  value       = var.target_languages
}

output "polly_voice_preferences" {
  description = "Voice preferences configured for Amazon Polly"
  value       = var.polly_voice_preferences
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used as prefix for resources"
  value       = var.project_name
}

output "resource_prefix" {
  description = "Complete resource prefix including random suffix"
  value       = local.resource_prefix
}

# ============================================================================
# Usage Examples
# ============================================================================

output "example_step_functions_execution_command" {
  description = "Example AWS CLI command to start a Step Functions execution"
  value = <<-EOT
    aws stepfunctions start-execution \
      --state-machine-arn "${aws_sfn_state_machine.voice_processing.arn}" \
      --name "test-execution-$(date +%Y%m%d-%H%M%S)" \
      --input '{
        "bucket": "${aws_s3_bucket.input.bucket}",
        "key": "test-audio.mp3",
        "job_id": "test-job-$(uuidgen)",
        "target_languages": ["es", "fr", "de"]
      }'
  EOT
}

output "example_s3_upload_command" {
  description = "Example AWS CLI command to upload audio file to input bucket"
  value = "aws s3 cp your-audio-file.mp3 s3://${aws_s3_bucket.input.bucket}/test-audio.mp3"
}

output "example_dynamodb_query_command" {
  description = "Example AWS CLI command to query job status"
  value = <<-EOT
    aws dynamodb get-item \
      --table-name "${aws_dynamodb_table.jobs.name}" \
      --key '{"JobId": {"S": "your-job-id"}}'
  EOT
}

# ============================================================================
# Validation and Testing Information
# ============================================================================

output "validation_checklist" {
  description = "Checklist for validating the deployed infrastructure"
  value = {
    s3_buckets_created = "Check that input and output S3 buckets exist and are accessible"
    dynamodb_table_ready = "Verify DynamoDB table is active and has the correct schema"
    lambda_functions_deployed = "Ensure all 5 Lambda functions are deployed successfully"
    step_functions_created = "Confirm Step Functions state machine is created and executable"
    iam_roles_configured = "Validate IAM roles have necessary permissions"
    monitoring_enabled = "Check CloudWatch alarms and monitoring are functioning"
    api_gateway_deployed = var.enable_api_gateway ? "Verify API Gateway is deployed and accessible" : "API Gateway not enabled"
    sns_notifications_setup = var.enable_sns_notifications ? "Confirm SNS topic and subscriptions are configured" : "SNS notifications not enabled"
  }
}

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    total_lambda_functions = 5
    s3_buckets = 2
    dynamodb_tables = 1
    step_functions = 1
    api_gateway_enabled = var.enable_api_gateway
    sns_notifications_enabled = var.enable_sns_notifications
    encryption_enabled = var.enable_encryption
    xray_tracing_enabled = var.enable_x_ray_tracing
    estimated_monthly_cost = "Varies based on usage volume - monitor with AWS Cost Explorer"
  }
}