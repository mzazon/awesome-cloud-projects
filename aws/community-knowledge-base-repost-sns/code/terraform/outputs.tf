# Outputs for Community Knowledge Base with re:Post Private and SNS infrastructure
# These outputs provide essential information for accessing and integrating with the deployed resources

#
# SNS Topic Outputs
#

output "sns_topic_arn" {
  description = "ARN of the SNS topic for knowledge base notifications"
  value       = aws_sns_topic.knowledge_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for knowledge base notifications"
  value       = aws_sns_topic.knowledge_notifications.name
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic"
  value       = aws_sns_topic.knowledge_notifications.display_name
}

output "sns_topic_id" {
  description = "ID of the SNS topic (same as ARN)"
  value       = aws_sns_topic.knowledge_notifications.id
}

#
# Subscription Information
#

output "email_subscription_count" {
  description = "Number of email subscriptions created"
  value       = length(aws_sns_topic_subscription.email_notifications)
}

output "email_subscription_arns" {
  description = "ARNs of all email subscriptions (will show as 'PendingConfirmation' until confirmed)"
  value       = aws_sns_topic_subscription.email_notifications[*].arn
}

output "notification_email_addresses" {
  description = "List of email addresses subscribed to notifications"
  value       = var.notification_email_addresses
  sensitive   = true # Mark as sensitive to avoid displaying emails in logs
}

#
# Dead Letter Queue Outputs (if enabled)
#

output "dead_letter_queue_url" {
  description = "URL of the dead letter queue (if enabled)"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].url : null
}

output "dead_letter_queue_arn" {
  description = "ARN of the dead letter queue (if enabled)"
  value       = var.enable_dead_letter_queue ? aws_sqs_queue.dlq[0].arn : null
}

#
# CloudWatch Monitoring Outputs
#

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for failed messages (if enabled)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.failed_messages[0].alarm_name : null
}

output "alarm_notification_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications (if enabled)"
  value       = var.enable_cloudwatch_alarms && var.cloudwatch_alarm_email != null ? aws_sns_topic.alarm_notifications[0].arn : null
}

#
# AWS Context Information
#

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

#
# Resource Names and Identifiers
#

output "resource_prefix" {
  description = "Common prefix used for all resource names"
  value       = "${var.project_name}-${var.environment}"
}

output "random_suffix" {
  description = "Random suffix added to resource names for uniqueness"
  value       = random_id.suffix.hex
}

#
# SSM Parameter Store References
#

output "ssm_parameter_sns_topic_arn" {
  description = "SSM parameter name storing the SNS topic ARN"
  value       = aws_ssm_parameter.sns_topic_arn.name
}

output "ssm_parameter_sns_topic_name" {
  description = "SSM parameter name storing the SNS topic name"
  value       = aws_ssm_parameter.sns_topic_name.name
}

#
# re:Post Private Information
#

output "repost_private_console_url" {
  description = "URL to access AWS re:Post Private console (requires Enterprise Support)"
  value       = "https://console.aws.amazon.com/repost-private/"
}

output "repost_private_requirements" {
  description = "Requirements for accessing re:Post Private"
  value = {
    support_plan_required = "Enterprise Support or Enterprise On-Ramp"
    iam_permissions      = "IAM Identity Center access or appropriate IAM permissions"
    manual_setup         = "re:Post Private requires manual configuration via AWS Console"
  }
}

#
# Integration Commands
#

output "sns_publish_command" {
  description = "AWS CLI command to publish test messages to the SNS topic"
  value = "aws sns publish --topic-arn ${aws_sns_topic.knowledge_notifications.arn} --subject 'Test Notification' --message 'This is a test message from your knowledge base notification system.'"
}

output "subscription_confirmation_note" {
  description = "Important note about email subscription confirmation"
  value = "Email subscriptions require manual confirmation. Check the email addresses for confirmation links."
}

#
# Cost Information
#

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = {
    sns_topic = "Free tier: First 1M requests/month, then $0.50 per 1M requests"
    email_notifications = "Free tier: First 1,000 email notifications/month, then $2.00 per 100,000 notifications"
    cloudwatch_alarms = var.enable_cloudwatch_alarms ? "First 10 alarms free, then $0.10 per alarm per month" : "Not enabled"
    sqs_dlq = var.enable_dead_letter_queue ? "Free tier: First 1M requests/month, then $0.40 per 1M requests" : "Not enabled"
    ssm_parameters = "Free tier: First 10,000 parameter operations/month, then $0.05 per 10,000 operations"
  }
}

#
# Next Steps and Documentation
#

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Confirm email subscriptions by clicking confirmation links sent to email addresses",
    "2. Access re:Post Private console at https://console.aws.amazon.com/repost-private/",
    "3. Complete re:Post Private initial configuration (requires Enterprise Support)",
    "4. Test the notification system using the provided AWS CLI command",
    "5. Review the generated setup guides in the terraform directory",
    "6. Configure your organization's knowledge base topics and branding"
  ]
}

output "setup_documentation_files" {
  description = "Generated documentation files for setup and onboarding"
  value = {
    repost_setup_guide = "${path.module}/repost-private-setup-guide.md"
    team_onboarding_checklist = "${path.module}/team-onboarding-checklist.md"
  }
}

#
# Security and Compliance Information
#

output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    sns_encryption = var.enable_sns_encryption ? "Enabled with AWS managed KMS key" : "Disabled"
    sqs_encryption = var.enable_dead_letter_queue ? "Enabled with AWS managed KMS key" : "Not applicable"
    iam_least_privilege = "Applied to all cross-service permissions"
    parameter_store_encryption = "Enabled by default for SecureString parameters"
  }
}

output "compliance_notes" {
  description = "Important compliance and governance notes"
  value = {
    data_residency = "All data remains within the configured AWS region (${data.aws_region.current.name})"
    audit_trail = "All SNS and SQS API calls are logged in CloudTrail (if enabled in your account)"
    email_privacy = "Email addresses are stored in Terraform state - ensure state is properly secured"
    enterprise_support = "re:Post Private requires Enterprise Support plan for compliance features"
  }
}