# =============================================================================
# OUTPUTS - Centralized Alert Management with User Notifications
# =============================================================================
# This file defines outputs that provide important information about the
# deployed infrastructure, including resource identifiers, ARNs, and 
# configuration details needed for verification and integration.
# =============================================================================

# =============================================================================
# S3 BUCKET INFORMATION
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket created for monitoring demonstration"
  value       = aws_s3_bucket.monitoring_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for IAM policy references and integrations"
  value       = aws_s3_bucket.monitoring_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket for direct access"
  value       = aws_s3_bucket.monitoring_bucket.bucket_domain_name
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket is deployed"
  value       = aws_s3_bucket.monitoring_bucket.region
}

output "s3_metrics_configuration" {
  description = "CloudWatch metrics configuration status for the S3 bucket"
  value = {
    entire_bucket_metrics = aws_s3_bucket_metric.entire_bucket_metrics.name
    request_metrics_enabled = var.enable_request_metrics
    request_metrics_prefix  = var.enable_request_metrics ? var.request_metrics_prefix : null
  }
}

# =============================================================================
# CLOUDWATCH ALARMS
# =============================================================================

output "cloudwatch_alarms" {
  description = "Details of CloudWatch alarms created for S3 monitoring"
  value = {
    bucket_size_alarm = {
      name        = aws_cloudwatch_metric_alarm.s3_bucket_size_alarm.alarm_name
      arn         = aws_cloudwatch_metric_alarm.s3_bucket_size_alarm.arn
      threshold   = var.bucket_size_threshold_bytes
      description = aws_cloudwatch_metric_alarm.s3_bucket_size_alarm.alarm_description
    }
    object_count_alarm = {
      name        = aws_cloudwatch_metric_alarm.s3_object_count_alarm.alarm_name
      arn         = aws_cloudwatch_metric_alarm.s3_object_count_alarm.arn
      threshold   = var.object_count_threshold
      description = aws_cloudwatch_metric_alarm.s3_object_count_alarm.alarm_description
    }
  }
}

output "alarm_thresholds" {
  description = "Configured alarm thresholds for monitoring reference"
  value = {
    bucket_size_bytes = var.bucket_size_threshold_bytes
    object_count      = var.object_count_threshold
    evaluation_periods = {
      bucket_size  = var.bucket_size_alarm_evaluation_periods
      object_count = var.object_count_alarm_evaluation_periods
    }
  }
}

# =============================================================================
# USER NOTIFICATIONS CONFIGURATION
# =============================================================================

output "notification_hub" {
  description = "AWS User Notifications hub configuration details"
  value = {
    region = aws_notifications_notification_hub.central_hub.notification_hub_region
    status = "Active"
  }
}

output "notification_configuration" {
  description = "Details of the User Notifications configuration"
  value = {
    name                 = aws_notifications_notification_configuration.s3_monitoring_config.name
    arn                  = aws_notifications_notification_configuration.s3_monitoring_config.arn
    aggregation_duration = var.notification_aggregation_duration
    description          = aws_notifications_notification_configuration.s3_monitoring_config.description
  }
}

output "email_contact" {
  description = "Email contact configuration for notifications"
  value = {
    name    = aws_notificationscontacts_email_contact.monitoring_contact.name
    arn     = aws_notificationscontacts_email_contact.monitoring_contact.arn
    email   = var.notification_email
    team    = var.contact_team
  }
  sensitive = true  # Mark as sensitive to avoid exposing email in logs
}

output "event_rule" {
  description = "EventBridge rule configuration for CloudWatch alarm integration"
  value = {
    name        = aws_notifications_event_rule.cloudwatch_alarm_rule.name
    description = aws_notifications_event_rule.cloudwatch_alarm_rule.description
    source      = "aws.cloudwatch"
    event_type  = "CloudWatch Alarm State Change"
  }
}

# =============================================================================
# TESTING AND VALIDATION
# =============================================================================

output "sample_data_created" {
  description = "Information about sample data objects created for testing"
  value = var.create_sample_data ? {
    sample_objects_count = 3
    large_file_created   = true
    bucket_path         = "s3://${aws_s3_bucket.monitoring_bucket.id}/"
  } : {
    sample_objects_count = 0
    large_file_created   = false
    message             = "Sample data creation disabled"
  }
}

output "monitoring_urls" {
  description = "AWS Console URLs for monitoring and management"
  value = {
    s3_console = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.monitoring_bucket.id}"
    cloudwatch_alarms = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:"
    user_notifications = "https://${data.aws_region.current.name}.console.aws.amazon.com/notifications/home?region=${data.aws_region.current.name}"
    notifications_center = "https://${data.aws_region.current.name}.console.aws.amazon.com/notifications/notifications"
  }
}

# =============================================================================
# COST AND BILLING INFORMATION
# =============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    s3_storage = "~$0.023 per GB stored (Standard storage class)"
    cloudwatch_alarms = "~$0.10 per alarm per month (2 alarms = $0.20)"
    request_metrics = var.enable_request_metrics ? "~$0.30 per 1,000 requests monitored" : "Disabled - no additional cost"
    user_notifications = "No additional charges for User Notifications service"
    total_estimated_monthly = var.enable_request_metrics ? "$0.20-$1.00" : "$0.20-$0.50"
    note = "Costs depend on actual usage and may vary by region"
  }
}

# =============================================================================
# SECURITY AND COMPLIANCE
# =============================================================================

output "security_configuration" {
  description = "Security settings applied to the infrastructure"
  value = {
    bucket_encryption = "AES256 server-side encryption enabled"
    public_access_blocked = "All public access blocked"
    versioning_enabled = "S3 bucket versioning enabled"
    https_only = "HTTPS-only access enforced through bucket policies"
  }
}

output "compliance_tags" {
  description = "Compliance and governance tags applied to resources"
  value = merge(local.common_tags, var.compliance_tags)
}

# =============================================================================
# INTEGRATION AND AUTOMATION
# =============================================================================

output "integration_details" {
  description = "Information for integrating with external systems"
  value = {
    eventbridge_integration = {
      source       = "aws.cloudwatch"
      detail_type  = "CloudWatch Alarm State Change"
      pattern_alarms = [
        aws_cloudwatch_metric_alarm.s3_bucket_size_alarm.alarm_name,
        aws_cloudwatch_metric_alarm.s3_object_count_alarm.alarm_name
      ]
    }
    api_endpoints = {
      notifications_api = "https://notifications.${data.aws_region.current.name}.amazonaws.com"
      cloudwatch_api   = "https://monitoring.${data.aws_region.current.name}.amazonaws.com"
    }
  }
}

# =============================================================================
# DEPLOYMENT INFORMATION
# =============================================================================

output "deployment_info" {
  description = "Information about the current deployment"
  value = {
    deployment_region = data.aws_region.current.name
    account_id       = data.aws_caller_identity.current.account_id
    terraform_version = "~> 1.0"
    aws_provider_version = "~> 5.0"
    deployment_timestamp = timestamp()
    resource_prefix = var.name_prefix
    environment = var.environment
  }
}

# =============================================================================
# TROUBLESHOOTING INFORMATION
# =============================================================================

output "troubleshooting_commands" {
  description = "AWS CLI commands for troubleshooting and verification"
  value = {
    check_bucket = "aws s3 ls s3://${aws_s3_bucket.monitoring_bucket.id}/"
    check_metrics = "aws s3api get-bucket-metrics-configuration --bucket ${aws_s3_bucket.monitoring_bucket.id} --id EntireBucketMetrics"
    check_alarms = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.s3_bucket_size_alarm.alarm_name} ${aws_cloudwatch_metric_alarm.s3_object_count_alarm.alarm_name}"
    check_notification_hub = "aws notifications list-notification-hubs --region ${data.aws_region.current.name}"
    check_email_contact = "aws notificationscontacts list-email-contacts"
    test_alarm = "aws cloudwatch set-alarm-state --alarm-name ${aws_cloudwatch_metric_alarm.s3_bucket_size_alarm.alarm_name} --state-value ALARM --state-reason 'Manual test'"
  }
}

# =============================================================================
# NEXT STEPS AND RECOMMENDATIONS
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    email_activation = "Check your email (${var.notification_email}) and activate the notification contact"
    console_access = "Visit the User Notifications Console to view the centralized notification center"
    testing = "Upload files to the S3 bucket or manually trigger alarms to test the notification system"
    customization = "Adjust alarm thresholds and notification settings based on your monitoring requirements"
    expansion = "Consider adding more CloudWatch alarms for comprehensive infrastructure monitoring"
  }
}