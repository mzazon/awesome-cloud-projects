# Video Stream Outputs
output "video_stream_name" {
  description = "Name of the Kinesis Video Stream"
  value       = aws_kinesisvideo_stream.video_stream.name
}

output "video_stream_arn" {
  description = "ARN of the Kinesis Video Stream"
  value       = aws_kinesisvideo_stream.video_stream.arn
}

# Face Collection Outputs
output "face_collection_id" {
  description = "ID of the Rekognition face collection"
  value       = aws_rekognition_collection.face_collection.collection_id
}

output "face_collection_arn" {
  description = "ARN of the Rekognition face collection"
  value       = aws_rekognition_collection.face_collection.arn
}

# Analytics Stream Outputs
output "analytics_stream_name" {
  description = "Name of the Kinesis Data Stream for analytics"
  value       = aws_kinesis_stream.analytics_stream.name
}

output "analytics_stream_arn" {
  description = "ARN of the Kinesis Data Stream for analytics"
  value       = aws_kinesis_stream.analytics_stream.arn
}

# DynamoDB Table Outputs
output "detections_table_name" {
  description = "Name of the DynamoDB table for detection events"
  value       = aws_dynamodb_table.detections.name
}

output "detections_table_arn" {
  description = "ARN of the DynamoDB table for detection events"
  value       = aws_dynamodb_table.detections.arn
}

output "faces_table_name" {
  description = "Name of the DynamoDB table for face metadata"
  value       = aws_dynamodb_table.faces.name
}

output "faces_table_arn" {
  description = "ARN of the DynamoDB table for face metadata"
  value       = aws_dynamodb_table.faces.arn
}

# Lambda Function Outputs
output "analytics_processor_function_name" {
  description = "Name of the analytics processor Lambda function"
  value       = aws_lambda_function.analytics_processor.function_name
}

output "analytics_processor_function_arn" {
  description = "ARN of the analytics processor Lambda function"
  value       = aws_lambda_function.analytics_processor.arn
}

output "query_api_function_name" {
  description = "Name of the query API Lambda function"
  value       = var.enable_api_gateway ? aws_lambda_function.query_api[0].function_name : null
}

output "query_api_function_arn" {
  description = "ARN of the query API Lambda function"
  value       = var.enable_api_gateway ? aws_lambda_function.query_api[0].arn : null
}

# SNS Topic Outputs
output "security_alerts_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "security_alerts_topic_name" {
  description = "Name of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.name
}

# API Gateway Outputs
output "api_gateway_url" {
  description = "URL of the API Gateway for video analytics queries"
  value       = var.enable_api_gateway ? aws_apigatewayv2_api.video_analytics_api[0].api_endpoint : null
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = var.enable_api_gateway ? aws_apigatewayv2_api.video_analytics_api[0].id : null
}

# IAM Role Outputs
output "video_analytics_role_arn" {
  description = "ARN of the IAM role for video analytics services"
  value       = aws_iam_role.video_analytics_role.arn
}

output "video_analytics_role_name" {
  description = "Name of the IAM role for video analytics services"
  value       = aws_iam_role.video_analytics_role.name
}

# KMS Key Outputs
output "kms_key_arn" {
  description = "ARN of the KMS key for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.video_analytics[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.video_analytics[0].key_id : null
}

output "kms_alias_name" {
  description = "Name of the KMS key alias (if enabled)"
  value       = var.enable_encryption ? aws_kms_alias.video_analytics[0].name : null
}

# Resource Naming Outputs
output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "name_suffix" {
  description = "Suffix used for unique resource naming"
  value       = local.name_suffix
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# CloudWatch Log Groups
output "analytics_processor_log_group" {
  description = "CloudWatch log group for analytics processor Lambda"
  value       = aws_cloudwatch_log_group.analytics_processor.name
}

output "query_api_log_group" {
  description = "CloudWatch log group for query API Lambda"
  value       = var.enable_api_gateway ? aws_cloudwatch_log_group.query_api[0].name : null
}

output "api_gateway_log_group" {
  description = "CloudWatch log group for API Gateway"
  value       = var.enable_api_gateway ? aws_cloudwatch_log_group.api_gateway[0].name : null
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed video analytics configuration"
  value = {
    video_stream_retention_hours = var.video_retention_hours
    face_match_threshold         = var.face_match_threshold
    kinesis_shard_count         = var.kinesis_shard_count
    lambda_batch_size           = var.lambda_batch_size
    dynamodb_read_capacity      = var.dynamodb_read_capacity
    dynamodb_write_capacity     = var.dynamodb_write_capacity
    encryption_enabled          = var.enable_encryption
    api_gateway_enabled         = var.enable_api_gateway
    alert_email_configured      = var.alert_email != ""
  }
}

# Next Steps Instructions
output "next_steps" {
  description = "Instructions for using the deployed video analytics infrastructure"
  value = {
    stream_processor_creation = "Create Rekognition stream processor using AWS CLI or Console with video stream ARN: ${aws_kinesisvideo_stream.video_stream.arn} and analytics stream ARN: ${aws_kinesis_stream.analytics_stream.arn}"
    face_collection_usage     = "Add faces to collection '${aws_rekognition_collection.face_collection.collection_id}' using AWS Rekognition Console or CLI"
    video_streaming          = "Send video to stream '${aws_kinesisvideo_stream.video_stream.name}' using KVS Producer SDK or GStreamer"
    api_testing             = var.enable_api_gateway ? "Test API endpoints at: ${aws_apigatewayv2_api.video_analytics_api[0].api_endpoint}" : "API Gateway not enabled"
    monitoring              = "Monitor CloudWatch logs for Lambda functions and set up CloudWatch dashboards for operational insights"
  }
}

# Cost Estimation Information
output "cost_considerations" {
  description = "Important cost considerations for the video analytics infrastructure"
  value = {
    primary_cost_drivers = [
      "Kinesis Video Streams ingestion and storage",
      "Rekognition stream processing per minute",
      "Lambda function execution time and memory",
      "DynamoDB read/write capacity units",
      "CloudWatch logs storage"
    ]
    cost_optimization_tips = [
      "Monitor video stream retention period",
      "Adjust DynamoDB capacity based on actual usage",
      "Use CloudWatch cost alerts",
      "Clean up test resources promptly",
      "Consider reserved capacity for production workloads"
    ]
  }
}