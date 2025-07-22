# ==============================================================================
# Multi-Region Backup Strategies - Outputs Configuration
# ==============================================================================
# This file defines all outputs that provide essential information about the
# deployed multi-region backup infrastructure. Outputs are organized by
# functional area and include both informational and integration values.
# ==============================================================================

# ==============================================================================
# Account and Region Information
# ==============================================================================

output "aws_account_id" {
  description = "AWS Account ID where the backup infrastructure is deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "primary_region" {
  description = "Primary AWS region for backup operations"
  value       = var.primary_region
}

output "secondary_region" {
  description = "Secondary AWS region for cross-region backup copies"
  value       = var.secondary_region
}

output "tertiary_region" {
  description = "Tertiary AWS region for long-term archival"
  value       = var.tertiary_region
}

output "deployment_timestamp" {
  description = "Timestamp when the backup infrastructure was deployed"
  value       = timestamp()
}

# ==============================================================================
# Backup Plan Information
# ==============================================================================

output "backup_plan_id" {
  description = "ID of the multi-region backup plan"
  value       = aws_backup_plan.multi_region.id
}

output "backup_plan_arn" {
  description = "ARN of the multi-region backup plan"
  value       = aws_backup_plan.multi_region.arn
}

output "backup_plan_name" {
  description = "Name of the multi-region backup plan"
  value       = aws_backup_plan.multi_region.name
}

output "backup_plan_version" {
  description = "Version of the backup plan (changes when plan is modified)"
  value       = aws_backup_plan.multi_region.version
}

output "backup_selection_id" {
  description = "ID of the backup selection for production resources"
  value       = aws_backup_selection.production_resources.id
}

# ==============================================================================
# Backup Vault Information
# ==============================================================================

output "primary_backup_vault" {
  description = "Information about the primary backup vault"
  value = {
    name               = aws_backup_vault.primary.name
    arn                = aws_backup_vault.primary.arn
    kms_key_arn        = aws_backup_vault.primary.kms_key_arn
    recovery_points    = aws_backup_vault.primary.recovery_points
    region             = var.primary_region
  }
}

output "secondary_backup_vault" {
  description = "Information about the secondary backup vault"
  value = {
    name               = aws_backup_vault.secondary.name
    arn                = aws_backup_vault.secondary.arn
    kms_key_arn        = aws_backup_vault.secondary.kms_key_arn
    recovery_points    = aws_backup_vault.secondary.recovery_points
    region             = var.secondary_region
  }
}

output "tertiary_backup_vault" {
  description = "Information about the tertiary backup vault"
  value = {
    name               = aws_backup_vault.tertiary.name
    arn                = aws_backup_vault.tertiary.arn
    kms_key_arn        = aws_backup_vault.tertiary.kms_key_arn
    recovery_points    = aws_backup_vault.tertiary.recovery_points
    region             = var.tertiary_region
  }
}

output "backup_vault_names" {
  description = "Map of all backup vault names by region"
  value = {
    primary   = aws_backup_vault.primary.name
    secondary = aws_backup_vault.secondary.name
    tertiary  = aws_backup_vault.tertiary.name
  }
}

output "backup_vault_arns" {
  description = "Map of all backup vault ARNs by region"
  value = {
    primary   = aws_backup_vault.primary.arn
    secondary = aws_backup_vault.secondary.arn
    tertiary  = aws_backup_vault.tertiary.arn
  }
}

# ==============================================================================
# IAM Role Information
# ==============================================================================

output "backup_service_role_arn" {
  description = "ARN of the AWS Backup service role"
  value       = aws_iam_role.backup_service_role.arn
}

output "backup_service_role_name" {
  description = "Name of the AWS Backup service role"
  value       = aws_iam_role.backup_service_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role for backup validation"
  value       = aws_iam_role.backup_validator_lambda_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role for backup validation"
  value       = aws_iam_role.backup_validator_lambda_role.name
}

# ==============================================================================
# Encryption and Security Information
# ==============================================================================

output "backup_kms_key_id" {
  description = "ID of the KMS key used for backup encryption in the primary region"
  value       = aws_kms_key.backup_key_primary.key_id
}

output "backup_kms_key_arn" {
  description = "ARN of the KMS key used for backup encryption in the primary region"
  value       = aws_kms_key.backup_key_primary.arn
}

output "backup_kms_key_alias" {
  description = "Alias of the KMS key used for backup encryption"
  value       = aws_kms_alias.backup_key_primary_alias.name
}

# ==============================================================================
# Monitoring and Notification Information
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for backup notifications"
  value       = aws_sns_topic.backup_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for backup notifications"
  value       = aws_sns_topic.backup_notifications.name
}

output "lambda_function_arn" {
  description = "ARN of the backup validation Lambda function"
  value       = aws_lambda_function.backup_validator.arn
}

output "lambda_function_name" {
  description = "Name of the backup validation Lambda function"
  value       = aws_lambda_function.backup_validator.function_name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.backup_validator_logs.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard for backup monitoring"
  value       = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.backup_monitoring.dashboard_name}"
}

# ==============================================================================
# EventBridge Rule Information
# ==============================================================================

output "eventbridge_rules" {
  description = "Information about EventBridge rules for backup monitoring"
  value = {
    backup_job_failure = {
      name = aws_cloudwatch_event_rule.backup_job_failure.name
      arn  = aws_cloudwatch_event_rule.backup_job_failure.arn
    }
    backup_job_completed = {
      name = aws_cloudwatch_event_rule.backup_job_completed.name
      arn  = aws_cloudwatch_event_rule.backup_job_completed.arn
    }
    copy_job_state_change = {
      name = aws_cloudwatch_event_rule.copy_job_state_change.name
      arn  = aws_cloudwatch_event_rule.copy_job_state_change.arn
    }
  }
}

# ==============================================================================
# Backup Configuration Summary
# ==============================================================================

output "backup_configuration" {
  description = "Summary of backup configuration settings"
  value = {
    daily_schedule         = var.daily_backup_schedule
    weekly_schedule        = var.weekly_backup_schedule
    daily_retention_days   = var.daily_retention_days
    weekly_retention_days  = var.weekly_retention_days
    daily_cold_storage     = var.daily_cold_storage_days
    weekly_cold_storage    = var.weekly_cold_storage_days
    start_window_minutes   = var.backup_start_window
    completion_window_minutes = var.backup_completion_window
    timezone              = var.backup_window_timezone
  }
}

output "resource_selection_criteria" {
  description = "Criteria used for automatic resource selection in backups"
  value = {
    required_tags = var.backup_resource_tags
    excluded_tags = var.exclude_resource_tags
    resource_types = length(var.resource_types_to_backup) > 0 ? var.resource_types_to_backup : ["All supported types"]
  }
}

# ==============================================================================
# Cross-Region Copy Configuration
# ==============================================================================

output "cross_region_copy_destinations" {
  description = "Information about cross-region copy destinations"
  value = {
    daily_backups = {
      source_vault      = aws_backup_vault.primary.name
      destination_vault = aws_backup_vault.secondary.name
      destination_region = var.secondary_region
    }
    weekly_backups = {
      source_vault      = aws_backup_vault.primary.name
      destination_vault = aws_backup_vault.tertiary.name
      destination_region = var.tertiary_region
    }
  }
}

# ==============================================================================
# Cost and Resource Management
# ==============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for backup infrastructure (excluding data storage)"
  value = {
    note = "Actual costs depend on data volume, cross-region transfers, and retention periods"
    components = {
      backup_storage = "Variable based on data volume and retention"
      cross_region_transfer = "Variable based on backup size and frequency"
      lambda_execution = "$0.00 - $5.00 (depending on backup job frequency)"
      sns_notifications = "$0.00 - $2.00 (depending on notification volume)"
      kms_key_usage = "$1.00 per key per month"
      cloudwatch_logs = "Variable based on log volume"
    }
  }
}

output "resource_tags" {
  description = "Tags applied to backup resources for cost allocation and management"
  value = local.common_tags
}

# ==============================================================================
# Operational Information
# ==============================================================================

output "backup_validation_enabled" {
  description = "Whether automated backup validation is enabled"
  value       = var.enable_lambda_validation
}

output "notification_configuration" {
  description = "Notification configuration details"
  value = {
    email_notifications   = var.notification_email != null ? "Enabled" : "Disabled"
    slack_notifications  = var.enable_slack_notifications ? "Enabled" : "Disabled"
    notification_events  = var.notification_events
  }
}

output "monitoring_configuration" {
  description = "Monitoring and alerting configuration"
  value = {
    eventbridge_monitoring = var.enable_eventbridge_monitoring
    detailed_monitoring   = var.enable_detailed_monitoring
    cloudwatch_dashboard  = var.create_cloudwatch_dashboard
    log_retention_days    = var.log_retention_days
  }
}

# ==============================================================================
# Next Steps and Usage Instructions
# ==============================================================================

output "next_steps" {
  description = "Next steps for completing the backup strategy implementation"
  value = {
    step_1 = "Tag your AWS resources with Environment=${var.environment} and BackupEnabled=true"
    step_2 = "Confirm SNS email subscription by checking your inbox and clicking the confirmation link"
    step_3 = "Review the CloudWatch dashboard at: https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.backup_monitoring.dashboard_name}"
    step_4 = "Test backup operations by manually triggering a backup job in the AWS Backup console"
    step_5 = "Monitor backup job execution through CloudWatch logs and EventBridge events"
    step_6 = "Review and adjust retention policies based on your compliance requirements"
  }
}

output "important_notes" {
  description = "Important notes and considerations for the backup strategy"
  value = {
    resource_tagging = "Only resources tagged with Environment=${var.environment} and BackupEnabled=true will be backed up"
    cross_region_costs = "Cross-region data transfer charges apply for backup copies to secondary and tertiary regions"
    retention_policies = "Ensure retention policies comply with your organization's data governance requirements"
    disaster_recovery = "Test disaster recovery procedures regularly using restore operations"
    monitoring = "Set up CloudWatch alarms for backup job failures and copy job monitoring"
    compliance = "Configure backup vault lock if your organization requires immutable backups for compliance"
  }
}

# ==============================================================================
# CLI Commands for Common Operations
# ==============================================================================

output "useful_cli_commands" {
  description = "Useful AWS CLI commands for managing the backup infrastructure"
  value = {
    list_backup_jobs = "aws backup list-backup-jobs --region ${var.primary_region}"
    list_copy_jobs = "aws backup list-copy-jobs --region ${var.secondary_region}"
    describe_backup_plan = "aws backup get-backup-plan --backup-plan-id ${aws_backup_plan.multi_region.id} --region ${var.primary_region}"
    list_recovery_points_primary = "aws backup list-recovery-points --backup-vault-name ${aws_backup_vault.primary.name} --region ${var.primary_region}"
    list_recovery_points_secondary = "aws backup list-recovery-points --backup-vault-name ${aws_backup_vault.secondary.name} --region ${var.secondary_region}"
    start_backup_job = "aws backup start-backup-job --backup-vault-name ${aws_backup_vault.primary.name} --resource-arn <RESOURCE_ARN> --iam-role-arn ${aws_iam_role.backup_service_role.arn} --region ${var.primary_region}"
    list_protected_resources = "aws backup list-protected-resources --region ${var.primary_region}"
  }
}

# ==============================================================================
# Integration Information
# ==============================================================================

output "integration_endpoints" {
  description = "Endpoints and ARNs for integrating with other AWS services"
  value = {
    backup_plan_arn = aws_backup_plan.multi_region.arn
    backup_service_role_arn = aws_iam_role.backup_service_role.arn
    sns_topic_arn = aws_sns_topic.backup_notifications.arn
    primary_vault_arn = aws_backup_vault.primary.arn
    secondary_vault_arn = aws_backup_vault.secondary.arn
    tertiary_vault_arn = aws_backup_vault.tertiary.arn
    kms_key_arn = aws_kms_key.backup_key_primary.arn
  }
}