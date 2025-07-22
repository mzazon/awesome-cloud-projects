# ========================================
# Outputs for Amazon Polly Text-to-Speech Infrastructure
# ========================================
# This file defines all outputs from the Polly TTS infrastructure deployment,
# providing essential information for application integration and management.

# ========================================
# S3 Bucket Outputs
# ========================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing synthesized audio files"
  value       = aws_s3_bucket.polly_audio_output.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing synthesized audio files"
  value       = aws_s3_bucket.polly_audio_output.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket for direct access"
  value       = aws_s3_bucket.polly_audio_output.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.polly_audio_output.bucket_regional_domain_name
}

output "s3_bucket_region" {
  description = "AWS region of the S3 bucket"
  value       = aws_s3_bucket.polly_audio_output.region
}

# ========================================
# IAM Role and Policy Outputs
# ========================================

output "polly_application_role_arn" {
  description = "ARN of the IAM role for Polly applications"
  value       = aws_iam_role.polly_application_role.arn
}

output "polly_application_role_name" {
  description = "Name of the IAM role for Polly applications"
  value       = aws_iam_role.polly_application_role.name
}

output "polly_instance_profile_arn" {
  description = "ARN of the IAM instance profile for EC2 instances"
  value       = aws_iam_instance_profile.polly_instance_profile.arn
}

output "polly_instance_profile_name" {
  description = "Name of the IAM instance profile for EC2 instances"
  value       = aws_iam_instance_profile.polly_instance_profile.name
}

output "polly_full_access_policy_arn" {
  description = "ARN of the IAM policy for full Polly access"
  value       = aws_iam_policy.polly_full_access_policy.arn
}

output "polly_s3_access_policy_arn" {
  description = "ARN of the IAM policy for S3 access"
  value       = aws_iam_policy.polly_s3_access_policy.arn
}

# ========================================
# CloudWatch Logging Outputs
# ========================================

output "application_log_group_name" {
  description = "Name of the CloudWatch log group for application logs"
  value       = aws_cloudwatch_log_group.polly_application_logs.name
}

output "application_log_group_arn" {
  description = "ARN of the CloudWatch log group for application logs"
  value       = aws_cloudwatch_log_group.polly_application_logs.arn
}

output "synthesis_log_group_name" {
  description = "Name of the CloudWatch log group for synthesis task logs"
  value       = aws_cloudwatch_log_group.polly_synthesis_logs.name
}

output "synthesis_log_group_arn" {
  description = "ARN of the CloudWatch log group for synthesis task logs"
  value       = aws_cloudwatch_log_group.polly_synthesis_logs.arn
}

# ========================================
# SNS Topic Outputs
# ========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for synthesis notifications"
  value       = aws_sns_topic.polly_synthesis_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for synthesis notifications"
  value       = aws_sns_topic.polly_synthesis_notifications.name
}

# ========================================
# Pronunciation Lexicon Outputs
# ========================================

output "tech_lexicon_name" {
  description = "Name of the technical terminology pronunciation lexicon"
  value       = aws_polly_lexicon.tech_terminology.name
}

output "tech_lexicon_arn" {
  description = "ARN of the technical terminology pronunciation lexicon"
  value       = aws_polly_lexicon.tech_terminology.arn
}

# ========================================
# Lambda Function Outputs (Conditional)
# ========================================

output "lambda_function_name" {
  description = "Name of the Lambda function for Polly processing"
  value       = var.create_lambda_function ? aws_lambda_function.polly_processor[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for Polly processing"
  value       = var.create_lambda_function ? aws_lambda_function.polly_processor[0].arn : null
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function for API Gateway integration"
  value       = var.create_lambda_function ? aws_lambda_function.polly_processor[0].invoke_arn : null
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for the Lambda function"
  value       = var.create_lambda_function ? aws_iam_role.polly_lambda_role[0].arn : null
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = var.create_lambda_function ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

# ========================================
# VPC Endpoint Outputs (Conditional)
# ========================================

output "polly_vpc_endpoint_id" {
  description = "ID of the VPC endpoint for Polly service"
  value       = var.vpc_id != "" ? aws_vpc_endpoint.polly_endpoint[0].id : null
}

output "polly_vpc_endpoint_dns_entries" {
  description = "DNS entries for the VPC endpoint"
  value       = var.vpc_id != "" ? aws_vpc_endpoint.polly_endpoint[0].dns_entry : null
}

output "polly_endpoint_security_group_id" {
  description = "Security group ID for the VPC endpoint"
  value       = var.vpc_id != "" ? aws_security_group.polly_endpoint_sg[0].id : null
}

# ========================================
# CloudWatch Monitoring Outputs
# ========================================

output "synthesis_failure_alarm_name" {
  description = "Name of the CloudWatch alarm for synthesis failures"
  value       = aws_cloudwatch_metric_alarm.synthesis_failure_alarm.alarm_name
}

output "synthesis_failure_alarm_arn" {
  description = "ARN of the CloudWatch alarm for synthesis failures"
  value       = aws_cloudwatch_metric_alarm.synthesis_failure_alarm.arn
}

output "synthesis_failure_metric_filter_name" {
  description = "Name of the CloudWatch metric filter for synthesis failures"
  value       = aws_cloudwatch_metric_filter.synthesis_failures.name
}

# ========================================
# Configuration Outputs
# ========================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "default_voice_id" {
  description = "Default voice ID configured for Polly synthesis"
  value       = var.default_voice_id
}

output "default_engine" {
  description = "Default synthesis engine configured for Polly"
  value       = var.default_engine
}

output "default_output_format" {
  description = "Default output format configured for synthesized audio"
  value       = var.default_output_format
}

output "supported_languages" {
  description = "List of supported languages for text-to-speech synthesis"
  value       = var.supported_languages
}

# ========================================
# Security and Compliance Outputs
# ========================================

output "encryption_at_rest_enabled" {
  description = "Whether encryption at rest is enabled for S3 bucket"
  value       = var.enable_encryption_at_rest
}

output "s3_versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.enable_s3_versioning
}

output "audio_file_retention_days" {
  description = "Number of days audio files are retained in S3"
  value       = var.audio_file_retention_days
}

output "log_retention_days" {
  description = "Number of days CloudWatch logs are retained"
  value       = var.log_retention_days
}

# ========================================
# Integration Outputs
# ========================================

output "polly_service_endpoints" {
  description = "Amazon Polly service endpoints for the region"
  value = {
    polly = "https://polly.${var.aws_region}.amazonaws.com"
    s3    = "https://s3.${var.aws_region}.amazonaws.com"
  }
}

output "sample_synthesis_command" {
  description = "Sample AWS CLI command for testing Polly synthesis"
  value = "aws polly synthesize-speech --text 'Hello from Amazon Polly!' --output-format mp3 --voice-id ${var.default_voice_id} --engine ${var.default_engine} --region ${var.aws_region} test-output.mp3"
}

output "sample_batch_synthesis_command" {
  description = "Sample AWS CLI command for batch synthesis"
  value = "aws polly start-speech-synthesis-task --output-format mp3 --output-s3-bucket-name ${aws_s3_bucket.polly_audio_output.bucket} --text 'This is a batch synthesis test.' --voice-id ${var.default_voice_id} --engine ${var.default_engine} --region ${var.aws_region}"
}

# ========================================
# Resource ARNs for Cross-Service Integration
# ========================================

output "resource_arns" {
  description = "ARNs of key resources for cross-service integration"
  value = {
    s3_bucket                = aws_s3_bucket.polly_audio_output.arn
    application_role         = aws_iam_role.polly_application_role.arn
    instance_profile         = aws_iam_instance_profile.polly_instance_profile.arn
    sns_topic               = aws_sns_topic.polly_synthesis_notifications.arn
    application_log_group   = aws_cloudwatch_log_group.polly_application_logs.arn
    synthesis_log_group     = aws_cloudwatch_log_group.polly_synthesis_logs.arn
    polly_full_access_policy = aws_iam_policy.polly_full_access_policy.arn
    polly_s3_access_policy  = aws_iam_policy.polly_s3_access_policy.arn
    lexicon                 = aws_polly_lexicon.tech_terminology.arn
    lambda_function         = var.create_lambda_function ? aws_lambda_function.polly_processor[0].arn : null
    vpc_endpoint            = var.vpc_id != "" ? aws_vpc_endpoint.polly_endpoint[0].id : null
  }
}

# ========================================
# Cost Optimization Outputs
# ========================================

output "cost_optimization_features" {
  description = "Cost optimization features enabled in the deployment"
  value = {
    s3_lifecycle_enabled        = var.enable_cost_optimization
    standard_to_ia_transition   = var.standard_to_ia_days
    ia_to_glacier_transition    = var.ia_to_glacier_days
    log_retention_optimization  = var.log_retention_days
    versioning_enabled          = var.enable_s3_versioning
  }
}

# ========================================
# Operational Outputs
# ========================================

output "operational_endpoints" {
  description = "Operational endpoints for monitoring and management"
  value = {
    cloudwatch_logs_url = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups"
    s3_console_url      = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.polly_audio_output.bucket}?region=${var.aws_region}&tab=objects"
    polly_console_url   = "https://${var.aws_region}.console.aws.amazon.com/polly/home?region=${var.aws_region}#/SynthesizeSpeech"
    iam_console_url     = "https://console.aws.amazon.com/iam/home?region=${var.aws_region}#/roles/${aws_iam_role.polly_application_role.name}"
  }
}

# ========================================
# Quick Start Configuration
# ========================================

output "quick_start_config" {
  description = "Quick start configuration for application developers"
  value = {
    s3_bucket_name      = aws_s3_bucket.polly_audio_output.bucket
    iam_role_arn        = aws_iam_role.polly_application_role.arn
    sns_topic_arn       = aws_sns_topic.polly_synthesis_notifications.arn
    lexicon_name        = aws_polly_lexicon.tech_terminology.name
    default_voice       = var.default_voice_id
    default_engine      = var.default_engine
    default_format      = var.default_output_format
    supported_languages = var.supported_languages
    aws_region          = var.aws_region
  }
}

# ========================================
# Environment Variables for Applications
# ========================================

output "environment_variables" {
  description = "Environment variables for application configuration"
  value = {
    POLLY_BUCKET_NAME         = aws_s3_bucket.polly_audio_output.bucket
    POLLY_ROLE_ARN           = aws_iam_role.polly_application_role.arn
    POLLY_SNS_TOPIC_ARN      = aws_sns_topic.polly_synthesis_notifications.arn
    POLLY_LEXICON_NAME       = aws_polly_lexicon.tech_terminology.name
    POLLY_DEFAULT_VOICE      = var.default_voice_id
    POLLY_DEFAULT_ENGINE     = var.default_engine
    POLLY_DEFAULT_FORMAT     = var.default_output_format
    POLLY_LOG_GROUP_NAME     = aws_cloudwatch_log_group.polly_application_logs.name
    AWS_REGION               = var.aws_region
    ENVIRONMENT              = var.environment
  }
}

# ========================================
# Security Configuration Summary
# ========================================

output "security_summary" {
  description = "Summary of security configurations applied"
  value = {
    s3_encryption_enabled     = var.enable_encryption_at_rest
    s3_public_access_blocked  = true
    iam_least_privilege       = true
    vpc_endpoint_enabled      = var.vpc_id != "" ? true : false
    cloudwatch_monitoring     = var.enable_cloudwatch_monitoring
    access_logging_enabled    = var.enable_access_logging
    audit_logging_enabled     = var.enable_audit_logging
  }
}

# ========================================
# Deployment Summary
# ========================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    deployment_region       = var.aws_region
    environment            = var.environment
    s3_bucket_created      = aws_s3_bucket.polly_audio_output.bucket
    iam_role_created       = aws_iam_role.polly_application_role.name
    lambda_function_created = var.create_lambda_function
    vpc_endpoint_created   = var.vpc_id != "" ? true : false
    monitoring_enabled     = var.enable_cloudwatch_monitoring
    lexicon_created        = aws_polly_lexicon.tech_terminology.name
    random_suffix          = random_string.suffix.result
  }
}