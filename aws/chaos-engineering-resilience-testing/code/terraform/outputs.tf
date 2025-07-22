# Output values for the AWS FIS and EventBridge chaos engineering infrastructure

output "fis_experiment_template_id" {
  description = "ID of the FIS experiment template"
  value       = aws_fis_experiment_template.chaos_experiment.id
}

output "fis_experiment_template_arn" {
  description = "ARN of the FIS experiment template"
  value       = aws_fis_experiment_template.chaos_experiment.arn
}

output "fis_experiment_role_arn" {
  description = "ARN of the IAM role used by FIS experiments"
  value       = aws_iam_role.fis_experiment_role.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for FIS notifications"
  value       = aws_sns_topic.fis_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for FIS notifications"
  value       = aws_sns_topic.fis_alerts.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for monitoring experiments"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.chaos_monitoring.dashboard_name}"
}

output "high_error_rate_alarm_arn" {
  description = "ARN of the CloudWatch alarm for high error rate (stop condition)"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.arn
}

output "high_cpu_alarm_arn" {
  description = "ARN of the CloudWatch alarm for high CPU utilization"
  value       = aws_cloudwatch_metric_alarm.high_cpu.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for FIS state changes"
  value       = aws_cloudwatch_event_rule.fis_state_changes.arn
}

output "experiment_schedule_arn" {
  description = "ARN of the EventBridge schedule for automated experiments (if enabled)"
  value       = var.enable_automated_schedule ? aws_scheduler_schedule.chaos_experiment_schedule[0].arn : null
}

output "notification_email" {
  description = "Email address configured for SNS notifications"
  value       = var.notification_email
  sensitive   = true
}

output "target_instance_tags" {
  description = "Tags used to identify target EC2 instances for chaos experiments"
  value       = var.target_instance_tags
}

output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

output "experiment_start_command" {
  description = "AWS CLI command to manually start the chaos experiment"
  value       = "aws fis start-experiment --experiment-template-id ${aws_fis_experiment_template.chaos_experiment.id} --region ${data.aws_region.current.name}"
}

output "experiment_status_command" {
  description = "AWS CLI command template to check experiment status (replace EXPERIMENT_ID)"
  value       = "aws fis get-experiment --id EXPERIMENT_ID --region ${data.aws_region.current.name}"
}

output "sns_subscription_confirmation" {
  description = "Instructions for confirming SNS email subscription"
  value       = "Check your email (${var.notification_email}) and click the confirmation link to receive FIS notifications"
}