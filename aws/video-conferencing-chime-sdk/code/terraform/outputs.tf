# Outputs for Amazon Chime SDK video conferencing solution
# This file defines all the important resource identifiers and URLs that will be displayed after deployment

# API Gateway outputs
output "api_gateway_url" {
  description = "URL of the deployed API Gateway for video conferencing backend"
  value       = "https://${aws_api_gateway_rest_api.video_conferencing_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.video_conferencing_api.id
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway deployment stage"
  value       = aws_api_gateway_stage.video_conferencing_api.stage_name
}

# Lambda function outputs
output "meeting_handler_function_name" {
  description = "Name of the meeting management Lambda function"
  value       = aws_lambda_function.meeting_handler.function_name
}

output "meeting_handler_function_arn" {
  description = "ARN of the meeting management Lambda function"
  value       = aws_lambda_function.meeting_handler.arn
}

output "attendee_handler_function_name" {
  description = "Name of the attendee management Lambda function"
  value       = aws_lambda_function.attendee_handler.function_name
}

output "attendee_handler_function_arn" {
  description = "ARN of the attendee management Lambda function"
  value       = aws_lambda_function.attendee_handler.arn
}

# DynamoDB outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for storing meeting metadata"
  value       = aws_dynamodb_table.meetings.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for storing meeting metadata"
  value       = aws_dynamodb_table.meetings.arn
}

# S3 bucket outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing meeting recordings"
  value       = aws_s3_bucket.recordings.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing meeting recordings"
  value       = aws_s3_bucket.recordings.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket for recordings"
  value       = aws_s3_bucket.recordings.bucket_domain_name
}

# SNS and SQS outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for Chime SDK event notifications"
  value       = aws_sns_topic.events.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for Chime SDK event notifications"
  value       = aws_sns_topic.events.name
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for processing Chime SDK events"
  value       = aws_sqs_queue.event_processing.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for processing Chime SDK events"
  value       = aws_sqs_queue.event_processing.arn
}

output "sqs_dlq_url" {
  description = "URL of the SQS dead letter queue for failed event processing"
  value       = aws_sqs_queue.event_processing_dlq.url
}

# IAM role outputs
output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Log Group outputs
output "meeting_handler_log_group_name" {
  description = "Name of the CloudWatch log group for meeting handler Lambda"
  value       = aws_cloudwatch_log_group.meeting_handler_logs.name
}

output "attendee_handler_log_group_name" {
  description = "Name of the CloudWatch log group for attendee handler Lambda"
  value       = aws_cloudwatch_log_group.attendee_handler_logs.name
}

# Resource naming outputs
output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name (dev, staging, prod)"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
  sensitive   = false
}

output "name_prefix" {
  description = "Common name prefix used for all resources"
  value       = local.name_prefix
}

# AWS account and region information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = true
}

# Sample API endpoints for quick reference
output "sample_api_endpoints" {
  description = "Sample API endpoints for testing the video conferencing solution"
  value = {
    create_meeting = "POST ${local.api_base_url}/meetings"
    get_meeting    = "GET ${local.api_base_url}/meetings/{meetingId}"
    delete_meeting = "DELETE ${local.api_base_url}/meetings/{meetingId}"
    create_attendee = "POST ${local.api_base_url}/meetings/{meetingId}/attendees"
    get_attendee   = "GET ${local.api_base_url}/meetings/{meetingId}/attendees/{attendeeId}"
    delete_attendee = "DELETE ${local.api_base_url}/meetings/{meetingId}/attendees/{attendeeId}"
  }
}

# Local value for API base URL (used in sample endpoints)
locals {
  api_base_url = "https://${aws_api_gateway_rest_api.video_conferencing_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
}

# Configuration values for client applications
output "client_configuration" {
  description = "Configuration values needed by client applications"
  value = {
    api_endpoint    = local.api_base_url
    aws_region     = data.aws_region.current.name
    bucket_name    = aws_s3_bucket.recordings.bucket
  }
}

# Monitoring and observability outputs (if enabled)
output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring (if detailed monitoring is enabled)"
  value = var.enable_detailed_monitoring ? {
    api_gateway_4xx_errors = try(aws_cloudwatch_metric_alarm.api_gateway_4xx_errors[0].arn, null)
    api_gateway_5xx_errors = try(aws_cloudwatch_metric_alarm.api_gateway_5xx_errors[0].arn, null)
    lambda_errors          = try(aws_cloudwatch_metric_alarm.lambda_errors[0].arn, null)
  } : null
}

# Quick start command examples
output "quick_start_commands" {
  description = "Quick start commands for testing the deployed infrastructure"
  value = {
    test_create_meeting = "curl -X POST '${local.api_base_url}/meetings' -H 'Content-Type: application/json' -d '{\"externalMeetingId\":\"test-meeting\",\"mediaRegion\":\"${data.aws_region.current.name}\"}'"
    check_dynamodb = "aws dynamodb scan --table-name ${aws_dynamodb_table.meetings.name} --region ${data.aws_region.current.name}"
    view_logs = "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${local.name_prefix}' --region ${data.aws_region.current.name}"
  }
}

# Cost optimization recommendations
output "cost_optimization_notes" {
  description = "Notes and recommendations for cost optimization"
  value = {
    notes = [
      "Consider using DynamoDB On-Demand billing for variable workloads",
      "Set S3 lifecycle policies to transition old recordings to cheaper storage classes",
      "Monitor API Gateway usage and adjust throttling limits as needed",
      "Use CloudWatch cost monitoring to track Chime SDK usage per attendee-minute",
      "Consider Lambda Provisioned Concurrency for consistent low-latency requirements"
    ]
    estimated_monthly_costs = {
      base_infrastructure = "~$20-40 (DynamoDB, S3, Lambda, API Gateway)"
      chime_sdk_usage = "Variable based on attendee-minutes"
      data_transfer = "Based on meeting traffic and recording downloads"
    }
  }
}

# Security considerations
output "security_notes" {
  description = "Security considerations and recommendations for production use"
  value = {
    current_setup = [
      "API Gateway endpoints are currently open (no authentication)",
      "S3 bucket has public access blocked",
      "DynamoDB uses IAM permissions for access control",
      "Lambda functions use least-privilege IAM roles"
    ]
    production_recommendations = [
      "Implement API authentication using Cognito User Pools or custom JWT",
      "Add request validation and rate limiting per user",
      "Enable AWS CloudTrail for audit logging",
      "Consider VPC endpoints for private API access",
      "Implement meeting access controls and participant verification",
      "Add encryption at rest for DynamoDB using customer-managed KMS keys",
      "Set up WAF rules for API Gateway protection"
    ]
  }
}