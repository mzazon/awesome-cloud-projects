# Outputs for Chat Notifications with SNS and Chatbot Infrastructure
# These outputs provide important information about the created resources
# for validation, testing, integration with other systems, and operational visibility.

# ============================================================================
# SNS TOPIC OUTPUTS
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for team notifications"
  value       = aws_sns_topic.team_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.team_notifications.name
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic"
  value       = aws_sns_topic.team_notifications.display_name
}

output "sns_topic_owner" {
  description = "AWS account ID that owns the SNS topic"
  value       = aws_sns_topic.team_notifications.owner
}

output "sns_topic_id" {
  description = "The ID of the SNS topic (same as ARN)"
  value       = aws_sns_topic.team_notifications.id
}

output "sns_topic_policy_arn" {
  description = "ARN of the SNS topic policy"
  value       = aws_sns_topic_policy.team_notifications_policy.arn
}

# ============================================================================
# CHATBOT SLACK OUTPUTS
# ============================================================================

output "chatbot_slack_configuration_arn" {
  description = "ARN of the AWS Chatbot Slack channel configuration"
  value       = length(aws_chatbot_slack_channel_configuration.team_alerts) > 0 ? aws_chatbot_slack_channel_configuration.team_alerts[0].chat_configuration_arn : null
}

output "chatbot_slack_configuration_name" {
  description = "Name of the AWS Chatbot Slack configuration"
  value       = length(aws_chatbot_slack_channel_configuration.team_alerts) > 0 ? aws_chatbot_slack_channel_configuration.team_alerts[0].configuration_name : null
}

output "chatbot_slack_channel_name" {
  description = "Name of the configured Slack channel"
  value       = length(aws_chatbot_slack_channel_configuration.team_alerts) > 0 ? aws_chatbot_slack_channel_configuration.team_alerts[0].slack_channel_name : null
}

output "chatbot_slack_team_name" {
  description = "Name of the configured Slack team/workspace"
  value       = length(aws_chatbot_slack_channel_configuration.team_alerts) > 0 ? aws_chatbot_slack_channel_configuration.team_alerts[0].slack_team_name : null
}

# ============================================================================
# CHATBOT TEAMS OUTPUTS
# ============================================================================

output "chatbot_teams_configuration_arn" {
  description = "ARN of the AWS Chatbot Teams channel configuration"
  value       = length(aws_chatbot_teams_channel_configuration.team_alerts_teams) > 0 ? aws_chatbot_teams_channel_configuration.team_alerts_teams[0].chat_configuration_arn : null
}

output "chatbot_teams_configuration_name" {
  description = "Name of the AWS Chatbot Teams configuration"
  value       = length(aws_chatbot_teams_channel_configuration.team_alerts_teams) > 0 ? aws_chatbot_teams_channel_configuration.team_alerts_teams[0].configuration_name : null
}

output "chatbot_teams_channel_name" {
  description = "Name of the configured Teams channel"
  value       = length(aws_chatbot_teams_channel_configuration.team_alerts_teams) > 0 ? aws_chatbot_teams_channel_configuration.team_alerts_teams[0].channel_name : null
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "chatbot_iam_role_arn" {
  description = "ARN of the IAM role used by AWS Chatbot"
  value       = aws_iam_role.chatbot_role.arn
}

output "chatbot_iam_role_name" {
  description = "Name of the IAM role used by AWS Chatbot"
  value       = aws_iam_role.chatbot_role.name
}

output "chatbot_iam_role_unique_id" {
  description = "Unique ID of the IAM role used by AWS Chatbot"
  value       = aws_iam_role.chatbot_role.unique_id
}

# ============================================================================
# CLOUDWATCH ALARMS OUTPUTS
# ============================================================================

output "demo_cpu_alarm_arn" {
  description = "ARN of the demo CPU utilization alarm"
  value       = length(aws_cloudwatch_metric_alarm.demo_cpu_alarm) > 0 ? aws_cloudwatch_metric_alarm.demo_cpu_alarm[0].arn : null
}

output "demo_cpu_alarm_name" {
  description = "Name of the demo CPU utilization alarm"
  value       = length(aws_cloudwatch_metric_alarm.demo_cpu_alarm) > 0 ? aws_cloudwatch_metric_alarm.demo_cpu_alarm[0].alarm_name : null
}

output "high_memory_alarm_arn" {
  description = "ARN of the high memory utilization alarm"
  value       = length(aws_cloudwatch_metric_alarm.high_memory_alarm) > 0 ? aws_cloudwatch_metric_alarm.high_memory_alarm[0].arn : null
}

output "high_memory_alarm_name" {
  description = "Name of the high memory utilization alarm"
  value       = length(aws_cloudwatch_metric_alarm.high_memory_alarm) > 0 ? aws_cloudwatch_metric_alarm.high_memory_alarm[0].alarm_name : null
}

output "application_error_rate_alarm_arn" {
  description = "ARN of the application error rate alarm"
  value       = length(aws_cloudwatch_metric_alarm.application_error_rate) > 0 ? aws_cloudwatch_metric_alarm.application_error_rate[0].arn : null
}

output "application_error_rate_alarm_name" {
  description = "Name of the application error rate alarm"
  value       = length(aws_cloudwatch_metric_alarm.application_error_rate) > 0 ? aws_cloudwatch_metric_alarm.application_error_rate[0].alarm_name : null
}

# ============================================================================
# MONITORING AND DASHBOARD OUTPUTS
# ============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for monitoring notifications"
  value = length(aws_cloudwatch_dashboard.notification_dashboard) > 0 ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.notification_dashboard[0].dashboard_name}" : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = length(aws_cloudwatch_dashboard.notification_dashboard) > 0 ? aws_cloudwatch_dashboard.notification_dashboard[0].dashboard_name : null
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_notification_command" {
  description = "AWS CLI command to send a test notification to the SNS topic"
  value = <<-EOT
aws sns publish \
  --topic-arn ${aws_sns_topic.team_notifications.arn} \
  --subject "🚨 Test Alert: Infrastructure Notification" \
  --message '{
    "AlarmName": "Manual Test Alert",
    "AlarmDescription": "Testing chat notification system deployment via Terraform",
    "NewStateValue": "ALARM", 
    "NewStateReason": "Testing notification delivery to chat platform from Terraform-deployed infrastructure",
    "StateChangeTime": "'$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")'"
  }' \
  --region ${data.aws_region.current.name}
EOT
}

output "sns_topic_verification_command" {
  description = "AWS CLI command to verify SNS topic configuration"
  value = <<-EOT
aws sns get-topic-attributes \
  --topic-arn ${aws_sns_topic.team_notifications.arn} \
  --query 'Attributes.{DisplayName:DisplayName,KmsMasterKeyId:KmsMasterKeyId,Policy:Policy,SubscriptionsConfirmed:SubscriptionsConfirmed}' \
  --region ${data.aws_region.current.name}
EOT
}

output "cloudwatch_alarm_verification_command" {
  description = "AWS CLI command to verify CloudWatch alarm status"
  value = length(aws_cloudwatch_metric_alarm.demo_cpu_alarm) > 0 ? <<-EOT
aws cloudwatch describe-alarms \
  --alarm-names ${aws_cloudwatch_metric_alarm.demo_cpu_alarm[0].alarm_name} \
  --query 'MetricAlarms[0].{Name:AlarmName,State:StateValue,Actions:AlarmActions,Description:AlarmDescription}' \
  --region ${data.aws_region.current.name}
EOT : "CloudWatch alarms are disabled. Set cloudwatch_alarm_enabled = true to enable."
}

output "sns_subscriptions_verification_command" {
  description = "AWS CLI command to list SNS topic subscriptions"
  value = <<-EOT
aws sns list-subscriptions-by-topic \
  --topic-arn ${aws_sns_topic.team_notifications.arn} \
  --query 'Subscriptions[*].{Protocol:Protocol,Endpoint:Endpoint,SubscriptionArn:SubscriptionArn,Confirmed:ConfirmationWasAuthenticated}' \
  --region ${data.aws_region.current.name}
EOT
}

output "chatbot_test_command" {
  description = "AWS CLI command to test chatbot functionality"
  value = local.chatbot_slack_enabled || local.chatbot_teams_enabled ? <<-EOT
# Send a formatted notification to test chatbot integration
aws sns publish \
  --topic-arn ${aws_sns_topic.team_notifications.arn} \
  --subject "🔔 Chatbot Integration Test" \
  --message '{
    "AlarmName": "Chatbot Integration Test",
    "AlarmDescription": "Verifying AWS Chatbot integration with chat platform",
    "NewStateValue": "OK",
    "NewStateReason": "Testing chatbot notification formatting and delivery",
    "StateChangeTime": "'$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")'"
  }' \
  --region ${data.aws_region.current.name}
EOT : "Chatbot integration not configured. Set slack_channel_id/slack_team_id or teams configuration variables."
}

# ============================================================================
# CONFIGURATION STATUS OUTPUTS
# ============================================================================

output "chatbot_slack_enabled" {
  description = "Whether AWS Chatbot Slack configuration is enabled"
  value       = local.chatbot_slack_enabled
}

output "chatbot_teams_enabled" {
  description = "Whether AWS Chatbot Teams configuration is enabled"
  value       = local.chatbot_teams_enabled
}

output "cloudwatch_alarms_enabled" {
  description = "Whether CloudWatch alarms are enabled"
  value       = var.cloudwatch_alarm_enabled
}

output "sns_encryption_enabled" {
  description = "Whether SNS topic encryption is enabled"
  value       = var.enable_sns_encryption
}

output "detailed_monitoring_enabled" {
  description = "Whether detailed monitoring is enabled"
  value       = var.enable_detailed_monitoring
}

output "cross_region_replication_enabled" {
  description = "Whether cross-region replication is enabled"
  value       = var.enable_cross_region_replication
}

output "additional_subscriptions_count" {
  description = "Number of additional SNS subscriptions configured"
  value       = length(var.additional_sns_subscriptions)
}

output "backup_regions_count" {
  description = "Number of backup regions configured for replication"
  value       = length(var.backup_regions)
}

# ============================================================================
# CROSS-REGION REPLICATION OUTPUTS
# ============================================================================

output "backup_sns_topics" {
  description = "ARNs of backup SNS topics in other regions"
  value = var.enable_cross_region_replication ? {
    for region in var.backup_regions : region => aws_sns_topic.backup_notifications[region].arn
  } : {}
}

# ============================================================================
# RESOURCE INFORMATION OUTPUTS
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_prefix" {
  description = "Common name prefix used for all resources"
  value       = local.name_prefix
}

output "resource_name_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.name_suffix
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
  sensitive   = false
}

# ============================================================================
# URL AND CONSOLE LINKS OUTPUTS
# ============================================================================

output "aws_console_sns_topic_url" {
  description = "AWS Console URL for the SNS topic"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home#/topic/${aws_sns_topic.team_notifications.arn}"
}

output "aws_console_chatbot_url" {
  description = "AWS Console URL for AWS Chatbot service"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/chatbot/home"
}

output "aws_console_cloudwatch_alarms_url" {
  description = "AWS Console URL for CloudWatch alarms"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home#alarmsV2:"
}

# ============================================================================
# MANUAL CONFIGURATION GUIDANCE OUTPUTS
# ============================================================================

output "deployment_status" {
  description = "Overall deployment status and next steps"
  value = {
    slack_configured  = local.chatbot_slack_enabled
    teams_configured  = local.chatbot_teams_enabled
    alarms_created   = var.cloudwatch_alarm_enabled
    encryption_enabled = var.enable_sns_encryption
    monitoring_enabled = var.enable_detailed_monitoring
    next_steps = local.chatbot_slack_enabled || local.chatbot_teams_enabled ? [
      "Test notifications using the test_notification_command output",
      "Verify chat platform integration in your channels",
      "Configure additional CloudWatch alarms as needed",
      "Set up additional SNS subscriptions if required"
    ] : [
      "Configure Slack or Teams integration by setting the appropriate variables",
      "Authorize AWS Chatbot in your chat platform workspace",
      "Run terraform apply again after configuration",
      "Test the notification system"
    ]
  }
}

output "manual_setup_instructions" {
  description = "Manual setup steps required after Terraform deployment"
  value = !local.chatbot_slack_enabled && !local.chatbot_teams_enabled ? <<-EOT

⚠️  MANUAL SETUP REQUIRED:

1. Choose your chat platform integration:

   For Slack:
   - Open AWS Chatbot console: https://console.aws.amazon.com/chatbot/
   - Choose 'Slack' as chat client
   - Click 'Configure' and authorize AWS Chatbot in your Slack workspace
   - Select your Slack workspace from dropdown
   - Note the Channel ID and Team ID for your target channel
   - Update terraform.tfvars with:
     slack_channel_id = "C07EZ1ABC23"  # Your channel ID
     slack_team_id    = "T07EA123LEP"  # Your team ID

   For Microsoft Teams:
   - Open AWS Chatbot console: https://console.aws.amazon.com/chatbot/
   - Choose 'Microsoft Teams' as chat client
   - Click 'Configure' and authorize AWS Chatbot in your Teams workspace
   - Note the Channel ID, Tenant ID, and Team ID
   - Update terraform.tfvars with:
     teams_channel_id = "your-channel-id"
     teams_tenant_id  = "your-tenant-id"
     teams_team_id    = "your-team-id"

2. Re-run Terraform:
   terraform apply

3. Test the integration:
   ${aws_sns_topic.team_notifications.arn}

4. Monitor in AWS Console:
   - SNS Topic: https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home#/topic/${aws_sns_topic.team_notifications.arn}
   - Chatbot: https://${data.aws_region.current.name}.console.aws.amazon.com/chatbot/home

EOT : <<-EOT

✅ DEPLOYMENT COMPLETE:

Your chat notification system is ready!

🔧 Infrastructure Created:
- SNS Topic: ${aws_sns_topic.team_notifications.name}
- IAM Role: ${aws_iam_role.chatbot_role.name}
${local.chatbot_slack_enabled ? "- Slack Integration: ${aws_chatbot_slack_channel_configuration.team_alerts[0].configuration_name}" : ""}
${local.chatbot_teams_enabled ? "- Teams Integration: ${aws_chatbot_teams_channel_configuration.team_alerts_teams[0].configuration_name}" : ""}
${var.cloudwatch_alarm_enabled ? "- Demo CloudWatch Alarms: Created for testing" : ""}

🧪 Test Your Setup:
${aws_sns_topic.team_notifications.arn}

📊 Monitor Your System:
- CloudWatch Dashboard: ${length(aws_cloudwatch_dashboard.notification_dashboard) > 0 ? "Created" : "Enable detailed monitoring to create"}
- SNS Topic Console: https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home#/topic/${aws_sns_topic.team_notifications.arn}

🎯 Next Steps:
1. Test notifications using the commands in the outputs
2. Configure additional CloudWatch alarms for your applications
3. Add email/SMS subscriptions via additional_sns_subscriptions variable
4. Set up cross-region replication for disaster recovery if needed

EOT
}