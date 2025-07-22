# Pinpoint Application Outputs
output "pinpoint_application_id" {
  description = "The ID of the Pinpoint application"
  value       = aws_pinpoint_app.mobile_ab_testing.application_id
}

output "pinpoint_application_arn" {
  description = "The ARN of the Pinpoint application"
  value       = aws_pinpoint_app.mobile_ab_testing.arn
}

output "pinpoint_application_name" {
  description = "The name of the Pinpoint application"
  value       = aws_pinpoint_app.mobile_ab_testing.name
}

# Segment Outputs
output "active_users_segment_id" {
  description = "The ID of the active users segment"
  value       = aws_pinpoint_segment.active_users.id
}

output "high_value_users_segment_id" {
  description = "The ID of the high-value users segment"
  value       = aws_pinpoint_segment.high_value_users.id
}

output "active_users_segment_arn" {
  description = "The ARN of the active users segment"
  value       = aws_pinpoint_segment.active_users.arn
}

output "high_value_users_segment_arn" {
  description = "The ARN of the high-value users segment"
  value       = aws_pinpoint_segment.high_value_users.arn
}

# S3 Bucket Outputs
output "analytics_export_bucket_name" {
  description = "The name of the S3 bucket for analytics export"
  value       = var.enable_analytics_export ? aws_s3_bucket.analytics_export[0].bucket : null
}

output "analytics_export_bucket_arn" {
  description = "The ARN of the S3 bucket for analytics export"
  value       = var.enable_analytics_export ? aws_s3_bucket.analytics_export[0].arn : null
}

output "analytics_export_bucket_domain_name" {
  description = "The domain name of the S3 bucket for analytics export"
  value       = var.enable_analytics_export ? aws_s3_bucket.analytics_export[0].bucket_domain_name : null
}

# Kinesis Stream Outputs
output "kinesis_stream_name" {
  description = "The name of the Kinesis stream for event processing"
  value       = var.enable_event_stream ? aws_kinesis_stream.pinpoint_events[0].name : null
}

output "kinesis_stream_arn" {
  description = "The ARN of the Kinesis stream for event processing"
  value       = var.enable_event_stream ? aws_kinesis_stream.pinpoint_events[0].arn : null
}

output "kinesis_stream_shard_count" {
  description = "The number of shards in the Kinesis stream"
  value       = var.enable_event_stream ? aws_kinesis_stream.pinpoint_events[0].shard_count : null
}

# IAM Role Outputs
output "pinpoint_s3_export_role_arn" {
  description = "The ARN of the IAM role for Pinpoint S3 export"
  value       = var.enable_analytics_export ? aws_iam_role.pinpoint_s3_export[0].arn : null
}

output "pinpoint_kinesis_export_role_arn" {
  description = "The ARN of the IAM role for Pinpoint Kinesis export"
  value       = var.enable_event_stream ? aws_iam_role.pinpoint_kinesis_export[0].arn : null
}

output "lambda_execution_role_arn" {
  description = "The ARN of the Lambda execution role"
  value       = var.create_winner_selection_lambda ? aws_iam_role.lambda_execution[0].arn : null
}

# Lambda Function Outputs
output "winner_selection_lambda_function_name" {
  description = "The name of the winner selection Lambda function"
  value       = var.create_winner_selection_lambda ? aws_lambda_function.winner_selection[0].function_name : null
}

output "winner_selection_lambda_function_arn" {
  description = "The ARN of the winner selection Lambda function"
  value       = var.create_winner_selection_lambda ? aws_lambda_function.winner_selection[0].arn : null
}

output "winner_selection_lambda_invoke_arn" {
  description = "The invoke ARN of the winner selection Lambda function"
  value       = var.create_winner_selection_lambda ? aws_lambda_function.winner_selection[0].invoke_arn : null
}

# CloudWatch Dashboard Outputs
output "cloudwatch_dashboard_name" {
  description = "The name of the CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.pinpoint_ab_testing[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "The URL of the CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.pinpoint_ab_testing[0].dashboard_name}" : null
}

# Push Notification Channel Outputs
output "gcm_channel_enabled" {
  description = "Whether the GCM/FCM channel is enabled"
  value       = var.firebase_server_key != "" ? true : false
}

output "apns_channel_enabled" {
  description = "Whether the APNS channel is enabled"
  value       = var.apns_certificate != "" && var.apns_private_key != "" ? true : false
}

output "apns_sandbox_mode" {
  description = "Whether APNS is in sandbox mode"
  value       = var.enable_apns_sandbox
}

# Configuration Outputs
output "campaign_configuration" {
  description = "Campaign configuration settings"
  value = {
    name                = var.campaign_name
    description         = var.campaign_description
    holdout_percentage  = var.holdout_percentage
    treatment_percentage = var.treatment_percentage
    daily_limit         = var.campaign_daily_limit
    total_limit         = var.campaign_total_limit
    messages_per_second = var.campaign_messages_per_second
  }
}

output "message_templates" {
  description = "Message template configurations"
  value = {
    control = {
      title = var.control_message_title
      body  = var.control_message_body
    }
    personalized = {
      title = var.personalized_message_title
      body  = var.personalized_message_body
    }
    urgent = {
      title = var.urgent_message_title
      body  = var.urgent_message_body
    }
  }
}

# Resource Identifiers
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Useful commands for getting started with the A/B testing setup"
  value = {
    check_application_status = "aws pinpoint get-app --application-id ${aws_pinpoint_app.mobile_ab_testing.application_id}"
    list_segments = "aws pinpoint get-segments --application-id ${aws_pinpoint_app.mobile_ab_testing.application_id}"
    view_dashboard = var.create_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.pinpoint_ab_testing[0].dashboard_name}" : "CloudWatch dashboard not created"
    create_test_endpoint = "aws pinpoint update-endpoint --application-id ${aws_pinpoint_app.mobile_ab_testing.application_id} --endpoint-id test-endpoint-001 --endpoint-request '{\"Address\":\"test@example.com\",\"ChannelType\":\"EMAIL\"}'"
  }
}

# Integration Instructions
output "integration_instructions" {
  description = "Instructions for integrating with your mobile application"
  value = {
    android_integration = "Add the Pinpoint SDK to your Android app and configure with Application ID: ${aws_pinpoint_app.mobile_ab_testing.application_id}"
    ios_integration = "Add the Pinpoint SDK to your iOS app and configure with Application ID: ${aws_pinpoint_app.mobile_ab_testing.application_id}"
    web_integration = "Add the Pinpoint JavaScript SDK to your web app and configure with Application ID: ${aws_pinpoint_app.mobile_ab_testing.application_id}"
    event_tracking = "Use the Pinpoint SDK to track custom events like 'conversion' with attributes and metrics"
  }
}

# Cost Estimation
output "cost_estimation" {
  description = "Estimated monthly costs for the A/B testing infrastructure"
  value = {
    note = "Costs vary based on usage. This is a rough estimate."
    pinpoint_messages = "~$0.01 per 1,000 messages sent"
    kinesis_stream = var.enable_event_stream ? "~$0.014 per hour per shard + $0.014 per million payload units" : "Not enabled"
    s3_storage = var.enable_analytics_export ? "~$0.023 per GB stored + request costs" : "Not enabled"
    lambda_execution = var.create_winner_selection_lambda ? "~$0.20 per million requests + compute time" : "Not enabled"
    cloudwatch_metrics = "~$0.30 per metric per month"
  }
}