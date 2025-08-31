# Outputs for website monitoring infrastructure

output "canary_name" {
  description = "Name of the CloudWatch Synthetics canary"
  value       = aws_synthetics_canary.website_monitor.name
}

output "canary_id" {
  description = "ID of the CloudWatch Synthetics canary"
  value       = aws_synthetics_canary.website_monitor.id
}

output "canary_arn" {
  description = "ARN of the CloudWatch Synthetics canary"
  value       = aws_synthetics_canary.website_monitor.arn
}

output "canary_status" {
  description = "Status of the CloudWatch Synthetics canary"
  value       = aws_synthetics_canary.website_monitor.status
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing canary artifacts"
  value       = aws_s3_bucket.synthetics_artifacts.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing canary artifacts"
  value       = aws_s3_bucket.synthetics_artifacts.arn
}

output "s3_bucket_url" {
  description = "URL of the S3 bucket storing canary artifacts"
  value       = "https://${aws_s3_bucket.synthetics_artifacts.bucket}.s3.${data.aws_region.current.name}.amazonaws.com"
}

output "iam_role_name" {
  description = "Name of the IAM role used by the canary"
  value       = aws_iam_role.synthetics_canary_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by the canary"
  value       = aws_iam_role.synthetics_canary_role.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.synthetics_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.synthetics_alerts.arn
}

output "failure_alarm_name" {
  description = "Name of the CloudWatch alarm for canary failures"
  value       = aws_cloudwatch_metric_alarm.canary_failure_alarm.alarm_name
}

output "failure_alarm_arn" {
  description = "ARN of the CloudWatch alarm for canary failures"
  value       = aws_cloudwatch_metric_alarm.canary_failure_alarm.arn
}

output "response_time_alarm_name" {
  description = "Name of the CloudWatch alarm for response time"
  value       = aws_cloudwatch_metric_alarm.canary_response_time_alarm.alarm_name
}

output "response_time_alarm_arn" {
  description = "ARN of the CloudWatch alarm for response time"
  value       = aws_cloudwatch_metric_alarm.canary_response_time_alarm.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard (if created)"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.website_monitoring[0].dashboard_name : null
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.website_monitoring[0].dashboard_name}" : null
}

output "canary_console_url" {
  description = "URL to view the canary in the AWS Console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/synthetics/home?region=${data.aws_region.current.name}#/canary/detail/${aws_synthetics_canary.website_monitor.name}"
}

output "monitored_website_url" {
  description = "The website URL being monitored"
  value       = var.website_url
}

output "canary_schedule" {
  description = "The schedule expression for the canary"
  value       = var.canary_schedule
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email
  sensitive   = true
}

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Common prefix used for resource naming"
  value       = local.resource_prefix
}

output "tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Validation outputs for testing
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_canary_status = "aws synthetics get-canary --name ${aws_synthetics_canary.website_monitor.name}"
    list_canary_runs    = "aws synthetics get-canary-runs --name ${aws_synthetics_canary.website_monitor.name} --max-results 5"
    check_s3_artifacts  = "aws s3 ls s3://${aws_s3_bucket.synthetics_artifacts.bucket}/canary-artifacts/ --recursive"
    check_alarms        = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.canary_failure_alarm.alarm_name} ${aws_cloudwatch_metric_alarm.canary_response_time_alarm.alarm_name}"
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the infrastructure"
  value = {
    synthetics_runs         = "~$53.57/month (5-minute intervals, $0.0012 per run after 100 free runs)"
    s3_storage             = "~$0.023/GB/month for Standard storage, ~$0.0125/GB/month for Standard-IA"
    cloudwatch_alarms      = "~$0.10/alarm/month"
    sns_notifications      = "~$0.50/million notifications"
    lambda_execution       = "Included in Synthetics pricing"
    notes                  = "Costs may vary based on actual usage, region, and AWS pricing changes"
  }
}