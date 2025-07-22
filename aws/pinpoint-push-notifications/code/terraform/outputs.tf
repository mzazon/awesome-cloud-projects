# Outputs for mobile push notifications with Pinpoint infrastructure

# ===================================
# Pinpoint Application Outputs
# ===================================

output "pinpoint_application_id" {
  description = "The unique identifier for the Pinpoint application"
  value       = aws_pinpoint_app.mobile_app.application_id
}

output "pinpoint_application_name" {
  description = "The name of the Pinpoint application"
  value       = aws_pinpoint_app.mobile_app.name
}

output "pinpoint_application_arn" {
  description = "The Amazon Resource Name (ARN) of the Pinpoint application"
  value       = aws_pinpoint_app.mobile_app.arn
}

# ===================================
# Channel Configuration Outputs
# ===================================

output "apns_channel_enabled" {
  description = "Whether the APNs channel is enabled for iOS notifications"
  value       = var.enable_apns
}

output "fcm_channel_enabled" {
  description = "Whether the FCM channel is enabled for Android notifications"
  value       = var.enable_fcm
}

output "apns_bundle_id" {
  description = "The iOS application bundle ID configured for APNs"
  value       = var.enable_apns ? var.apns_bundle_id : null
}

# ===================================
# Segmentation Outputs
# ===================================

output "segment_id" {
  description = "The unique identifier for the user segment"
  value       = aws_pinpoint_segment.high_value_customers.segment_id
}

output "segment_name" {
  description = "The name of the user segment"
  value       = aws_pinpoint_segment.high_value_customers.name
}

output "segment_arn" {
  description = "The Amazon Resource Name (ARN) of the user segment"
  value       = aws_pinpoint_segment.high_value_customers.arn
}

# ===================================
# Template Outputs
# ===================================

output "push_template_name" {
  description = "The name of the push notification template"
  value       = var.create_push_template ? aws_pinpoint_push_template.notification_template[0].template_name : null
}

output "push_template_arn" {
  description = "The Amazon Resource Name (ARN) of the push notification template"
  value       = var.create_push_template ? aws_pinpoint_push_template.notification_template[0].arn : null
}

# ===================================
# Test Endpoint Outputs
# ===================================

output "ios_test_endpoint_id" {
  description = "The identifier for the iOS test endpoint"
  value       = var.create_test_endpoints ? aws_pinpoint_endpoint.ios_test_endpoint[0].endpoint_id : null
}

output "android_test_endpoint_id" {
  description = "The identifier for the Android test endpoint"
  value       = var.create_test_endpoints ? aws_pinpoint_endpoint.android_test_endpoint[0].endpoint_id : null
}

# ===================================
# Campaign Outputs
# ===================================

output "campaign_id" {
  description = "The unique identifier for the sample push notification campaign"
  value       = var.create_test_endpoints ? aws_pinpoint_campaign.flash_sale[0].campaign_id : null
}

output "campaign_name" {
  description = "The name of the sample push notification campaign"
  value       = var.create_test_endpoints ? aws_pinpoint_campaign.flash_sale[0].name : null
}

output "campaign_arn" {
  description = "The Amazon Resource Name (ARN) of the sample campaign"
  value       = var.create_test_endpoints ? aws_pinpoint_campaign.flash_sale[0].arn : null
}

# ===================================
# Analytics and Monitoring Outputs
# ===================================

output "kinesis_stream_name" {
  description = "The name of the Kinesis stream for event analytics"
  value       = var.enable_event_streaming ? aws_kinesis_stream.pinpoint_events[0].name : null
}

output "kinesis_stream_arn" {
  description = "The Amazon Resource Name (ARN) of the Kinesis stream"
  value       = var.enable_event_streaming ? aws_kinesis_stream.pinpoint_events[0].arn : null
}

output "event_streaming_enabled" {
  description = "Whether event streaming to Kinesis is enabled"
  value       = var.enable_event_streaming
}

output "cloudwatch_log_group_name" {
  description = "The name of the CloudWatch log group for Pinpoint logs"
  value       = aws_cloudwatch_log_group.pinpoint_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "The Amazon Resource Name (ARN) of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.pinpoint_logs.arn
}

# ===================================
# IAM and Security Outputs
# ===================================

output "pinpoint_service_role_arn" {
  description = "The Amazon Resource Name (ARN) of the Pinpoint service role"
  value       = aws_iam_role.pinpoint_service_role.arn
}

output "pinpoint_service_role_name" {
  description = "The name of the Pinpoint service role"
  value       = aws_iam_role.pinpoint_service_role.name
}

# ===================================
# Alarm and Notification Outputs
# ===================================

output "sns_alarm_topic_arn" {
  description = "The Amazon Resource Name (ARN) of the SNS topic for alarm notifications"
  value       = var.enable_cloudwatch_alarms && var.alarm_notification_email != "" ? aws_sns_topic.alarm_notifications[0].arn : null
}

output "push_failures_alarm_name" {
  description = "The name of the CloudWatch alarm for push notification failures"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.push_failures[0].alarm_name : null
}

output "delivery_rate_alarm_name" {
  description = "The name of the CloudWatch alarm for delivery rate monitoring"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.delivery_rate[0].alarm_name : null
}

# ===================================
# Configuration Summary Outputs
# ===================================

output "quiet_time_configuration" {
  description = "The configured quiet time settings for notifications"
  value = {
    start = var.quiet_time_start
    end   = var.quiet_time_end
  }
}

output "notification_configuration" {
  description = "The default notification title and body configuration"
  value = {
    title = var.notification_title
    body  = var.notification_body
  }
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.resource_suffix
}

# ===================================
# Next Steps and Usage Information
# ===================================

output "next_steps" {
  description = "Instructions for next steps after deployment"
  value = <<-EOF
  Mobile Push Notification Infrastructure Deployed Successfully!
  
  Next Steps:
  1. Configure APNs certificates/keys if enabling iOS notifications
  2. Add FCM server key if enabling Android notifications
  3. Update mobile applications with Pinpoint SDK integration
  4. Create additional user endpoints as users register
  5. Set up additional segments for targeted campaigns
  6. Monitor delivery metrics in CloudWatch
  
  Key Resources:
  - Pinpoint Application ID: ${aws_pinpoint_app.mobile_app.application_id}
  - AWS Console: https://console.aws.amazon.com/pinpoint/home?region=${data.aws_region.current.name}#/apps/${aws_pinpoint_app.mobile_app.application_id}
  
  AWS CLI Commands for Testing:
  - List endpoints: aws pinpoint get-endpoints --application-id ${aws_pinpoint_app.mobile_app.application_id}
  - Get analytics: aws pinpoint get-application-date-range-kpi --application-id ${aws_pinpoint_app.mobile_app.application_id} --kpi-name unique-endpoints
  EOF
}

# ===================================
# Cost Estimation Outputs
# ===================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the infrastructure"
  value = {
    pinpoint_base    = "Free tier: 5,000 targeted users/month"
    pinpoint_messages = "$1.00 per 1M messages (after free tier)"
    kinesis_stream   = var.enable_event_streaming ? "$0.014 per shard hour (~$10/month)" : "Not enabled"
    cloudwatch_logs  = "$0.50 per GB ingested"
    sns_notifications = "$0.50 per 1M notifications"
    total_estimate   = "$10-50/month for 100K messages"
  }
}