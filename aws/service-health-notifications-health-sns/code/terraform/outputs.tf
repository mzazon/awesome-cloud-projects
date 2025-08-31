# Outputs for AWS Health Notifications Infrastructure
# These outputs provide important information about the created resources
# for verification, integration, and operational reference

output "sns_topic_arn" {
  description = "ARN of the SNS topic for health notifications"
  value       = aws_sns_topic.health_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for health notifications"
  value       = aws_sns_topic.health_notifications.name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule monitoring health events"
  value       = aws_cloudwatch_event_rule.health_events.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule monitoring health events"
  value       = aws_cloudwatch_event_rule.health_events.arn
}

output "eventbridge_rule_state" {
  description = "Current state of the EventBridge rule (ENABLED/DISABLED)"
  value       = aws_cloudwatch_event_rule.health_events.is_enabled ? "ENABLED" : "DISABLED"
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by EventBridge to publish to SNS"
  value       = aws_iam_role.eventbridge_sns_role.arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by EventBridge"
  value       = aws_iam_role.eventbridge_sns_role.name
}

output "email_subscriptions" {
  description = "List of email addresses subscribed to health notifications"
  value       = [for subscription in aws_sns_topic_subscription.email_notifications : subscription.endpoint]
}

output "subscription_confirmation_required" {
  description = "List of email subscriptions requiring manual confirmation"
  value = [
    for subscription in aws_sns_topic_subscription.email_notifications :
    subscription.endpoint if subscription.confirmation_was_authenticated == false
  ]
}

output "event_pattern" {
  description = "Event pattern used by the EventBridge rule"
  value       = local.event_pattern
  sensitive   = false
}

output "deployment_summary" {
  description = "Summary of the deployed health notification system"
  value = {
    sns_topic_arn           = aws_sns_topic.health_notifications.arn
    eventbridge_rule_name   = aws_cloudwatch_event_rule.health_events.name
    rule_enabled           = aws_cloudwatch_event_rule.health_events.is_enabled
    email_count            = length(aws_sns_topic_subscription.email_notifications)
    aws_account_id         = data.aws_caller_identity.current.account_id
    aws_region             = data.aws_region.current.name
    resource_name_suffix   = local.name_suffix
  }
}

output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Check email inbox(es) for SNS subscription confirmation messages",
    "2. Click the confirmation links in the emails to activate subscriptions",
    "3. Verify the EventBridge rule is enabled and monitoring health events",
    "4. Test the notification system using the AWS CLI or console",
    "5. Monitor AWS Personal Health Dashboard for any ongoing service events"
  ]
}

output "testing_commands" {
  description = "AWS CLI commands for testing the notification system"
  value = {
    test_sns_publish = "aws sns publish --topic-arn ${aws_sns_topic.health_notifications.arn} --subject 'Test Health Notification' --message 'Test message to verify notification system'"
    check_rule_status = "aws events describe-rule --name ${aws_cloudwatch_event_rule.health_events.name}"
    list_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.health_notifications.arn}"
    check_rule_targets = "aws events list-targets-by-rule --rule ${aws_cloudwatch_event_rule.health_events.name}"
  }
}

output "cost_estimation" {
  description = "Estimated monthly costs for the health notification system"
  value = {
    sns_topic = "Free (within AWS Free Tier limits)"
    eventbridge_rule = "Free (first 14 million events per month)"
    sns_email_notifications = "$0.50 per 1 million notifications"
    iam_role = "Free"
    estimated_monthly_cost = "< $1 USD for typical usage"
    note = "Costs may vary based on notification volume and AWS Free Tier eligibility"
  }
}

output "troubleshooting_guide" {
  description = "Common troubleshooting steps and considerations"
  value = {
    email_not_received = "Check spam/junk folders and ensure email addresses are correct"
    subscription_pending = "Email subscriptions require manual confirmation via email link"
    no_health_events = "Health events are triggered by actual AWS service issues - test with sns:Publish"
    rule_disabled = "Ensure the EventBridge rule is enabled in the AWS console or via CLI"
    permissions_error = "Verify IAM role has sns:Publish permissions for the target topic"
    monitoring = "Use CloudWatch Logs and EventBridge metrics to monitor rule execution"
  }
}