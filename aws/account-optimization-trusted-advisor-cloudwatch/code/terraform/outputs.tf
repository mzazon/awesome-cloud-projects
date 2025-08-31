# ==============================================================================
# Terraform Outputs for AWS Trusted Advisor CloudWatch Monitoring
# ==============================================================================
# This file defines all output values from the Trusted Advisor monitoring 
# infrastructure deployment, providing essential information for verification,
# integration with other systems, and operational management.
# ==============================================================================

# ==============================================================================
# SNS Topic Information
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for Trusted Advisor alerts. Use this ARN to subscribe additional endpoints or integrate with other AWS services."
  value       = aws_sns_topic.trusted_advisor_alerts.arn
  sensitive   = false
}

output "sns_topic_name" {
  description = "Name of the SNS topic for Trusted Advisor alerts. This can be used for CLI operations and references in other configurations."
  value       = aws_sns_topic.trusted_advisor_alerts.name
  sensitive   = false
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic shown in email notifications and AWS console."
  value       = aws_sns_topic.trusted_advisor_alerts.display_name
  sensitive   = false
}

# ==============================================================================
# Email Subscription Information
# ==============================================================================

output "email_subscriptions" {
  description = "List of email subscription ARNs created for Trusted Advisor notifications. These subscriptions require manual confirmation via email."
  value = [
    for subscription in aws_sns_topic_subscription.email_notifications : {
      arn                 = subscription.arn
      endpoint            = subscription.endpoint
      protocol            = subscription.protocol
      confirmation_status = subscription.confirmation_was_authenticated
    }
  ]
  sensitive = true # Email addresses are considered sensitive information
}

output "subscription_confirmation_required" {
  description = "Indicates whether email subscription confirmations are pending. Recipients must click confirmation links in their email."
  value       = length(var.notification_emails) > 0
  sensitive   = false
}

# ==============================================================================
# CloudWatch Alarm Information
# ==============================================================================

output "cloudwatch_alarms" {
  description = "Comprehensive information about all created CloudWatch alarms for operational monitoring and troubleshooting."
  value = {
    cost_optimization = {
      name        = aws_cloudwatch_metric_alarm.cost_optimization.alarm_name
      arn         = aws_cloudwatch_metric_alarm.cost_optimization.arn
      description = aws_cloudwatch_metric_alarm.cost_optimization.alarm_description
      metric_name = aws_cloudwatch_metric_alarm.cost_optimization.metric_name
      namespace   = aws_cloudwatch_metric_alarm.cost_optimization.namespace
      threshold   = aws_cloudwatch_metric_alarm.cost_optimization.threshold
      check_name  = "Low Utilization Amazon EC2 Instances"
    }
    security = {
      name        = aws_cloudwatch_metric_alarm.security_monitoring.alarm_name
      arn         = aws_cloudwatch_metric_alarm.security_monitoring.arn
      description = aws_cloudwatch_metric_alarm.security_monitoring.alarm_description
      metric_name = aws_cloudwatch_metric_alarm.security_monitoring.metric_name
      namespace   = aws_cloudwatch_metric_alarm.security_monitoring.namespace
      threshold   = aws_cloudwatch_metric_alarm.security_monitoring.threshold
      check_name  = "Security Groups - Specific Ports Unrestricted"
    }
    service_limits = {
      name        = aws_cloudwatch_metric_alarm.service_limits.alarm_name
      arn         = aws_cloudwatch_metric_alarm.service_limits.arn
      description = aws_cloudwatch_metric_alarm.service_limits.alarm_description
      metric_name = aws_cloudwatch_metric_alarm.service_limits.metric_name
      namespace   = aws_cloudwatch_metric_alarm.service_limits.namespace
      threshold   = aws_cloudwatch_metric_alarm.service_limits.threshold
      check_name  = "Running On-Demand EC2 Instances"
    }
  }
  sensitive = false
}

# ==============================================================================
# Optional Alarm Information
# ==============================================================================

output "optional_alarms" {
  description = "Information about optional Trusted Advisor check alarms that were enabled through variables."
  value = {
    iam_key_rotation = var.enable_iam_key_rotation_alarm ? {
      name = aws_cloudwatch_metric_alarm.iam_key_rotation[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.iam_key_rotation[0].arn
      enabled = true
    } : { enabled = false }
    
    rds_security = var.enable_rds_security_alarm ? {
      name = aws_cloudwatch_metric_alarm.rds_security[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.rds_security[0].arn
      enabled = true
    } : { enabled = false }
    
    s3_permissions = var.enable_s3_permissions_alarm ? {
      name = aws_cloudwatch_metric_alarm.s3_permissions[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.s3_permissions[0].arn
      enabled = true
    } : { enabled = false }
  }
  sensitive = false
}

# ==============================================================================
# Resource Naming and Identification
# ==============================================================================

output "resource_prefix" {
  description = "The prefix used for naming all resources created by this module. Useful for identifying related resources in the AWS console."
  value       = local.resource_prefix
  sensitive   = false
}

output "random_suffix" {
  description = "The random suffix used in resource names to ensure uniqueness across deployments."
  value       = random_id.suffix.hex
  sensitive   = false
}

# ==============================================================================
# AWS Account and Region Information
# ==============================================================================

output "aws_account_id" {
  description = "AWS account ID where the resources were deployed. This is useful for cross-account integrations and IAM policy references."
  value       = data.aws_caller_identity.current.account_id
  sensitive   = false
}

output "aws_region" {
  description = "AWS region where the resources were deployed. Note that Trusted Advisor metrics are only available in us-east-1."
  value       = data.aws_region.current.name
  sensitive   = false
}

output "trusted_advisor_region_note" {
  description = "Important note about Trusted Advisor region requirements for operational teams."
  value       = "All Trusted Advisor metrics are published to us-east-1 region regardless of resource location. Ensure monitoring is deployed in us-east-1 for complete functionality."
  sensitive   = false
}

# ==============================================================================
# Configuration Summary
# ==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed configuration for documentation and operational reference."
  value = {
    project_name              = var.project_name
    environment              = var.environment
    notification_emails_count = length(var.notification_emails)
    alarm_evaluation_period  = var.alarm_evaluation_period
    cost_threshold           = var.cost_optimization_threshold
    security_threshold       = var.security_threshold
    service_limits_threshold = var.service_limits_threshold
    optional_alarms_enabled = {
      iam_key_rotation = var.enable_iam_key_rotation_alarm
      rds_security     = var.enable_rds_security_alarm
      s3_permissions   = var.enable_s3_permissions_alarm
    }
    deployment_timestamp = timestamp()
  }
  sensitive = false
}

# ==============================================================================
# Operational Commands
# ==============================================================================

output "aws_cli_commands" {
  description = "Useful AWS CLI commands for managing and monitoring the deployed infrastructure."
  value = {
    # SNS Topic operations
    test_notification = "aws sns publish --topic-arn ${aws_sns_topic.trusted_advisor_alerts.arn} --message 'Test notification from Trusted Advisor monitoring' --subject 'Test Alert'"
    list_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.trusted_advisor_alerts.arn}"
    
    # CloudWatch operations
    describe_alarms = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.cost_optimization.alarm_name} ${aws_cloudwatch_metric_alarm.security_monitoring.alarm_name} ${aws_cloudwatch_metric_alarm.service_limits.alarm_name}"
    check_alarm_history = "aws cloudwatch describe-alarm-history --alarm-name ${aws_cloudwatch_metric_alarm.cost_optimization.alarm_name} --max-records 5"
    
    # Trusted Advisor metrics
    list_ta_metrics = "aws cloudwatch list-metrics --namespace AWS/TrustedAdvisor --region us-east-1"
    get_cost_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/TrustedAdvisor --metric-name YellowResources --dimensions Name=CheckName,Value='Low Utilization Amazon EC2 Instances' --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 3600 --statistics Average --region us-east-1"
  }
  sensitive = false
}

# ==============================================================================
# Cost Estimation Information
# ==============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources to help with budget planning."
  value = {
    sns_notifications = "Approximately $0.50-$2.00 per month based on alert frequency (first 1,000 notifications per month are free)"
    cloudwatch_alarms = "First 10 alarms are free, then $0.10 per alarm per month"
    data_transfer = "Minimal costs for SNS message delivery within AWS regions"
    total_estimate = "Typically $0.50-$3.00 per month for standard usage"
    note = "Actual costs depend on alert frequency, number of email recipients, and AWS Free Tier eligibility"
  }
  sensitive = false
}

# ==============================================================================
# Validation and Testing Information
# ==============================================================================

output "validation_steps" {
  description = "Steps to validate that the monitoring system is working correctly."
  value = {
    step_1 = "Confirm email subscriptions by checking your inbox and clicking confirmation links"
    step_2 = "Send test notification: aws sns publish --topic-arn ${aws_sns_topic.trusted_advisor_alerts.arn} --message 'Test' --subject 'Test'"
    step_3 = "Check alarm states: aws cloudwatch describe-alarms --query 'MetricAlarms[*].[AlarmName,StateValue]' --output table"
    step_4 = "Verify Trusted Advisor metrics: aws cloudwatch list-metrics --namespace AWS/TrustedAdvisor --region us-east-1"
    step_5 = "Review alarm history after 24 hours for any state changes"
  }
  sensitive = false
}

# ==============================================================================
# Integration Information
# ==============================================================================

output "integration_endpoints" {
  description = "Information for integrating with external monitoring and incident management systems."
  value = {
    webhook_integration = "Use SNS HTTP/HTTPS subscriptions to integrate with webhook-based systems like Slack, PagerDuty, or Microsoft Teams"
    sqs_integration = "Subscribe SQS queues to the SNS topic for asynchronous processing of alerts"
    lambda_integration = "Subscribe Lambda functions to the SNS topic for custom alert processing and automated remediation"
    api_endpoints = {
      sns_topic_arn = aws_sns_topic.trusted_advisor_alerts.arn
      region = data.aws_region.current.name
    }
  }
  sensitive = false
}

# ==============================================================================
# Security and Compliance Information
# ==============================================================================

output "security_considerations" {
  description = "Security and compliance information for the deployed monitoring system."
  value = {
    encryption = "SNS topic is encrypted using ${var.sns_kms_key_id}"
    iam_permissions = "CloudWatch alarms have permissions to publish to SNS topic via service-linked role"
    data_sensitivity = "Trusted Advisor alerts may contain account-specific information - ensure appropriate access controls"
    compliance_tags = "All resources are tagged according to the specified compliance framework: ${var.compliance_framework}"
    retention_policy = "CloudWatch logs and SNS message history retained for ${var.retention_period_days} days"
  }
  sensitive = false
}

# ==============================================================================
# Troubleshooting Information
# ==============================================================================

output "troubleshooting_guide" {
  description = "Common troubleshooting steps and diagnostic commands for the monitoring system."
  value = {
    no_notifications = "Check email confirmation status and SNS topic policy permissions"
    alarm_stuck_insufficient_data = "Trusted Advisor metrics may take several hours to appear - this is normal behavior"
    missing_metrics = "Ensure you have Business, Enterprise On-Ramp, or Enterprise Support plan for full Trusted Advisor access"
    wrong_region = "All operations must be performed in us-east-1 region for Trusted Advisor metrics"
    high_costs = "Monitor SNS usage in CloudWatch and adjust notification frequency if needed"
    false_alarms = "Consider adjusting threshold values or evaluation periods to reduce alert sensitivity"
  }
  sensitive = false
}