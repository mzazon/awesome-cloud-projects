# ====================================
# BACKUP VAULT OUTPUTS
# ====================================

output "primary_backup_vault_name" {
  description = "Name of the primary backup vault"
  value       = aws_backup_vault.primary.name
}

output "primary_backup_vault_arn" {
  description = "ARN of the primary backup vault"
  value       = aws_backup_vault.primary.arn
}

output "dr_backup_vault_name" {
  description = "Name of the disaster recovery backup vault"
  value       = aws_backup_vault.dr.name
}

output "dr_backup_vault_arn" {
  description = "ARN of the disaster recovery backup vault"
  value       = aws_backup_vault.dr.arn
}

output "primary_backup_vault_recovery_points" {
  description = "Number of recovery points in primary backup vault"
  value       = aws_backup_vault.primary.recovery_points
}

output "dr_backup_vault_recovery_points" {
  description = "Number of recovery points in DR backup vault"
  value       = aws_backup_vault.dr.recovery_points
}

# ====================================
# BACKUP PLAN OUTPUTS
# ====================================

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = aws_backup_plan.enterprise_backup.id
}

output "backup_plan_arn" {
  description = "ARN of the backup plan"
  value       = aws_backup_plan.enterprise_backup.arn
}

output "backup_plan_name" {
  description = "Name of the backup plan"
  value       = aws_backup_plan.enterprise_backup.name
}

output "backup_plan_version" {
  description = "Version of the backup plan"
  value       = aws_backup_plan.enterprise_backup.version
}

# ====================================
# IAM ROLE OUTPUTS
# ====================================

output "backup_service_role_arn" {
  description = "ARN of the AWS Backup service role"
  value       = aws_iam_role.backup_service_role.arn
}

output "backup_service_role_name" {
  description = "Name of the AWS Backup service role"
  value       = aws_iam_role.backup_service_role.name
}

output "backup_service_role_unique_id" {
  description = "Unique ID of the AWS Backup service role"
  value       = aws_iam_role.backup_service_role.unique_id
}

# ====================================
# ENCRYPTION OUTPUTS
# ====================================

output "primary_backup_kms_key_id" {
  description = "ID of the KMS key used for backup encryption in primary region"
  value       = aws_kms_key.backup_key.key_id
}

output "primary_backup_kms_key_arn" {
  description = "ARN of the KMS key used for backup encryption in primary region"
  value       = aws_kms_key.backup_key.arn
}

output "dr_backup_kms_key_id" {
  description = "ID of the KMS key used for backup encryption in DR region"
  value       = aws_kms_key.backup_key_dr.key_id
}

output "dr_backup_kms_key_arn" {
  description = "ARN of the KMS key used for backup encryption in DR region"
  value       = aws_kms_key.backup_key_dr.arn
}

output "primary_backup_kms_alias_name" {
  description = "Alias name of the KMS key in primary region"
  value       = aws_kms_alias.backup_key_alias.name
}

output "dr_backup_kms_alias_name" {
  description = "Alias name of the KMS key in DR region"
  value       = aws_kms_alias.backup_key_alias_dr.name
}

# ====================================
# MONITORING AND NOTIFICATION OUTPUTS
# ====================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for backup notifications"
  value       = aws_sns_topic.backup_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for backup notifications"
  value       = aws_sns_topic.backup_notifications.name
}

output "backup_failure_alarm_name" {
  description = "Name of the CloudWatch alarm for backup job failures"
  value       = aws_cloudwatch_metric_alarm.backup_job_failures.alarm_name
}

output "backup_storage_alarm_name" {
  description = "Name of the CloudWatch alarm for backup storage usage"
  value       = aws_cloudwatch_metric_alarm.backup_storage_usage.alarm_name
}

# ====================================
# REPORTING OUTPUTS
# ====================================

output "backup_reports_bucket_name" {
  description = "Name of the S3 bucket for backup reports"
  value       = aws_s3_bucket.backup_reports.bucket
}

output "backup_reports_bucket_arn" {
  description = "ARN of the S3 bucket for backup reports"
  value       = aws_s3_bucket.backup_reports.arn
}

output "backup_report_plan_name" {
  description = "Name of the backup report plan"
  value       = var.enable_backup_reporting ? aws_backup_report_plan.backup_compliance_report[0].name : null
}

output "backup_report_plan_arn" {
  description = "ARN of the backup report plan"
  value       = var.enable_backup_reporting ? aws_backup_report_plan.backup_compliance_report[0].arn : null
}

# ====================================
# COMPLIANCE OUTPUTS
# ====================================

output "config_rule_name" {
  description = "Name of the AWS Config rule for backup compliance"
  value       = var.enable_config_compliance ? aws_config_config_rule.backup_plan_compliance[0].name : null
}

output "config_rule_arn" {
  description = "ARN of the AWS Config rule for backup compliance"
  value       = var.enable_config_compliance ? aws_config_config_rule.backup_plan_compliance[0].arn : null
}

# ====================================
# RESTORE TESTING OUTPUTS
# ====================================

output "restore_testing_plan_name" {
  description = "Name of the automated restore testing plan"
  value       = var.enable_restore_testing ? aws_backup_restore_testing_plan.automated_restore_test[0].name : null
}

output "restore_testing_plan_arn" {
  description = "ARN of the automated restore testing plan"
  value       = var.enable_restore_testing ? aws_backup_restore_testing_plan.automated_restore_test[0].arn : null
}

# ====================================
# SECURITY OUTPUTS
# ====================================

output "backup_vault_lock_enabled" {
  description = "Whether backup vault lock is enabled"
  value       = var.enable_backup_vault_lock
}

output "backup_vault_policy_attached" {
  description = "Whether access policy is attached to backup vault"
  value       = true
}

# ====================================
# RESOURCE SELECTION OUTPUTS
# ====================================

output "production_backup_selection_id" {
  description = "ID of the production resources backup selection"
  value       = aws_backup_selection.production_resources.selection_id
}

output "critical_databases_backup_selection_id" {
  description = "ID of the critical databases backup selection"
  value       = aws_backup_selection.critical_databases.selection_id
}

# ====================================
# OPERATIONAL OUTPUTS
# ====================================

output "primary_region" {
  description = "Primary AWS region where backup resources are deployed"
  value       = var.primary_region
}

output "dr_region" {
  description = "Disaster recovery AWS region for cross-region backup replication"
  value       = var.dr_region
}

output "environment" {
  description = "Environment name for the backup solution"
  value       = var.environment
}

output "backup_schedule_daily" {
  description = "Daily backup schedule expression"
  value       = var.daily_backup_schedule
}

output "backup_schedule_weekly" {
  description = "Weekly backup schedule expression"
  value       = var.weekly_backup_schedule
}

output "backup_schedule_monthly" {
  description = "Monthly backup schedule expression"
  value       = var.monthly_backup_schedule
}

output "backup_retention_daily_days" {
  description = "Daily backup retention period in days"
  value       = var.daily_backup_retention_days
}

output "backup_retention_weekly_days" {
  description = "Weekly backup retention period in days"
  value       = var.weekly_backup_retention_days
}

output "backup_retention_monthly_days" {
  description = "Monthly backup retention period in days"
  value       = var.monthly_backup_retention_days
}

# ====================================
# CROSS-REGION REPLICATION OUTPUTS
# ====================================

output "cross_region_replication_enabled" {
  description = "Whether cross-region backup replication is enabled"
  value       = true
}

output "cross_region_copy_destinations" {
  description = "List of destination regions for backup copies"
  value       = [var.dr_region]
}

# ====================================
# COST OPTIMIZATION OUTPUTS
# ====================================

output "lifecycle_policies_enabled" {
  description = "Whether backup lifecycle policies are enabled for cost optimization"
  value       = true
}

output "continuous_backup_enabled" {
  description = "Whether continuous backup is enabled for supported resources"
  value       = var.enable_continuous_backup
}

# ====================================
# SUMMARY OUTPUTS
# ====================================

output "backup_solution_summary" {
  description = "Summary of the deployed backup solution"
  value = {
    primary_vault_name      = aws_backup_vault.primary.name
    dr_vault_name          = aws_backup_vault.dr.name
    backup_plan_name       = aws_backup_plan.enterprise_backup.name
    sns_topic_name         = aws_sns_topic.backup_notifications.name
    reports_bucket_name    = aws_s3_bucket.backup_reports.bucket
    service_role_name      = aws_iam_role.backup_service_role.name
    kms_key_primary        = aws_kms_key.backup_key.key_id
    kms_key_dr            = aws_kms_key.backup_key_dr.key_id
    monitoring_enabled     = true
    cross_region_enabled   = true
    compliance_enabled     = var.enable_config_compliance
    restore_testing_enabled = var.enable_restore_testing
  }
}

# ====================================
# VERIFICATION COMMANDS
# ====================================

output "verification_commands" {
  description = "AWS CLI commands to verify the backup solution deployment"
  value = {
    list_backup_plans = "aws backup list-backup-plans --region ${var.primary_region}"
    list_backup_vaults = "aws backup list-backup-vaults --region ${var.primary_region}"
    list_backup_jobs = "aws backup list-backup-jobs --by-backup-vault-name ${aws_backup_vault.primary.name} --region ${var.primary_region}"
    check_sns_subscriptions = "aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.backup_notifications.arn} --region ${var.primary_region}"
    check_cloudwatch_alarms = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.backup_job_failures.alarm_name} ${aws_cloudwatch_metric_alarm.backup_storage_usage.alarm_name} --region ${var.primary_region}"
    verify_cross_region_vaults = "aws backup list-backup-vaults --region ${var.dr_region}"
  }
}