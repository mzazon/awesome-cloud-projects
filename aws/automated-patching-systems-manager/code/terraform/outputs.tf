# Output Values for Automated Patching Infrastructure
# This file defines the output values that will be displayed after deployment

# ==============================================================================
# PATCH BASELINE OUTPUTS
# ==============================================================================

output "patch_baseline_id" {
  description = "ID of the custom patch baseline"
  value       = aws_ssm_patch_baseline.custom.id
}

output "patch_baseline_name" {
  description = "Name of the custom patch baseline"
  value       = aws_ssm_patch_baseline.custom.name
}

output "patch_baseline_arn" {
  description = "ARN of the custom patch baseline"
  value       = aws_ssm_patch_baseline.custom.arn
}

output "patch_group" {
  description = "Name of the patch group"
  value       = var.patch_group
}

# ==============================================================================
# MAINTENANCE WINDOW OUTPUTS
# ==============================================================================

output "patch_maintenance_window_id" {
  description = "ID of the patch installation maintenance window"
  value       = aws_ssm_maintenance_window.patch_installation.id
}

output "patch_maintenance_window_name" {
  description = "Name of the patch installation maintenance window"
  value       = aws_ssm_maintenance_window.patch_installation.name
}

output "scan_maintenance_window_id" {
  description = "ID of the patch scanning maintenance window"
  value       = aws_ssm_maintenance_window.patch_scanning.id
}

output "scan_maintenance_window_name" {
  description = "Name of the patch scanning maintenance window"
  value       = aws_ssm_maintenance_window.patch_scanning.name
}

output "maintenance_window_schedule" {
  description = "Schedule for the patch installation maintenance window"
  value       = var.maintenance_window_schedule
}

output "scan_window_schedule" {
  description = "Schedule for the patch scanning maintenance window"
  value       = var.scan_window_schedule
}

# ==============================================================================
# TARGET CONFIGURATION OUTPUTS
# ==============================================================================

output "target_tag_key" {
  description = "Tag key used for targeting EC2 instances"
  value       = var.target_tag_key
}

output "target_tag_value" {
  description = "Tag value used for targeting EC2 instances"
  value       = var.target_tag_value
}

output "patch_target_id" {
  description = "ID of the patch installation target"
  value       = aws_ssm_maintenance_window_target.patch_targets.id
}

output "scan_target_id" {
  description = "ID of the patch scanning target"
  value       = aws_ssm_maintenance_window_target.scan_targets.id
}

# ==============================================================================
# TASK CONFIGURATION OUTPUTS
# ==============================================================================

output "patch_task_id" {
  description = "ID of the patch installation task"
  value       = aws_ssm_maintenance_window_task.patch_installation.id
}

output "scan_task_id" {
  description = "ID of the patch scanning task"
  value       = aws_ssm_maintenance_window_task.patch_scanning.id
}

output "max_concurrency" {
  description = "Maximum concurrency setting for patch installation"
  value       = var.max_concurrency
}

output "max_errors" {
  description = "Maximum errors setting for patch installation"
  value       = var.max_errors
}

# ==============================================================================
# IAM ROLE OUTPUTS
# ==============================================================================

output "maintenance_window_role_arn" {
  description = "ARN of the maintenance window IAM role"
  value       = aws_iam_role.maintenance_window.arn
}

output "maintenance_window_role_name" {
  description = "Name of the maintenance window IAM role"
  value       = aws_iam_role.maintenance_window.name
}

# ==============================================================================
# STORAGE OUTPUTS
# ==============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for patch logs"
  value       = aws_s3_bucket.patch_logs.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for patch logs"
  value       = aws_s3_bucket.patch_logs.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket for patch logs"
  value       = aws_s3_bucket.patch_logs.region
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for patch operations"
  value       = aws_cloudwatch_log_group.patch_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for patch operations"
  value       = aws_cloudwatch_log_group.patch_logs.arn
}

# ==============================================================================
# MONITORING AND NOTIFICATIONS OUTPUTS
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for patch notifications"
  value       = aws_sns_topic.patch_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for patch notifications"
  value       = aws_sns_topic.patch_notifications.name
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for patch compliance"
  value       = var.enable_patch_compliance_monitoring ? aws_cloudwatch_metric_alarm.patch_compliance[0].alarm_name : "Not enabled"
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for patch management"
  value       = aws_cloudwatch_dashboard.patch_management.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.patch_management.dashboard_name}"
}

# ==============================================================================
# CONFIGURATION SUMMARY OUTPUTS
# ==============================================================================

output "patch_configuration_summary" {
  description = "Summary of patch configuration settings"
  value = {
    operating_system        = var.patch_baseline_operating_system
    classification_filters  = var.patch_classification_filters
    approve_after_days     = var.patch_approve_after_days
    compliance_level       = var.patch_compliance_level
    maintenance_duration   = var.maintenance_window_duration
    scan_duration         = var.scan_window_duration
    environment           = var.environment
    patch_group           = var.patch_group
  }
}

# ==============================================================================
# USEFUL COMMANDS OUTPUTS
# ==============================================================================

output "useful_commands" {
  description = "Useful AWS CLI commands for managing the patching infrastructure"
  value = {
    check_patch_compliance = "aws ssm describe-instance-patch-states --query 'InstancePatchStates[*].[InstanceId,PatchGroup,BaselineId,OperationEndTime]' --output table"
    list_maintenance_windows = "aws ssm describe-maintenance-windows --query 'WindowIdentities[*].[WindowId,Name,NextExecutionTime]' --output table"
    get_patch_baseline_info = "aws ssm describe-patch-baselines --baseline-ids ${aws_ssm_patch_baseline.custom.id}"
    view_patch_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.patch_logs.name}"
    test_sns_notification = "aws sns publish --topic-arn ${aws_sns_topic.patch_notifications.arn} --message 'Test notification' --subject 'Patch Management Test'"
  }
}

# ==============================================================================
# RESOURCE IDENTIFIERS
# ==============================================================================

output "resource_name_prefix" {
  description = "Prefix used for resource names"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique naming"
  value       = random_string.suffix.result
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# ==============================================================================
# NOTIFICATION CONFIGURATION
# ==============================================================================

output "notification_email" {
  description = "Email address configured for notifications (if provided)"
  value       = var.notification_email != "" ? var.notification_email : "Not configured"
  sensitive   = true
}

output "email_subscription_pending" {
  description = "Whether email subscription confirmation is pending"
  value       = var.notification_email != "" ? "Check your email for subscription confirmation" : "No email configured"
}