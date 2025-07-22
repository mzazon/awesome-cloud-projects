# Outputs for AWS Multi-Region Backup Strategy
# These outputs provide essential information about the created backup infrastructure
# for monitoring, integration, and validation purposes

# ========================================
# Backup Plan and Vault Information
# ========================================

output "backup_plan_id" {
  description = "The ID of the multi-region backup plan"
  value       = aws_backup_plan.multi_region.id
}

output "backup_plan_arn" {
  description = "The ARN of the multi-region backup plan"
  value       = aws_backup_plan.multi_region.arn
}

output "backup_plan_name" {
  description = "The name of the multi-region backup plan"
  value       = aws_backup_plan.multi_region.name
}

output "primary_backup_vault_name" {
  description = "The name of the primary backup vault"
  value       = aws_backup_vault.primary.name
}

output "primary_backup_vault_arn" {
  description = "The ARN of the primary backup vault"
  value       = aws_backup_vault.primary.arn
}

output "secondary_backup_vault_name" {
  description = "The name of the secondary backup vault"
  value       = aws_backup_vault.secondary.name
}

output "secondary_backup_vault_arn" {
  description = "The ARN of the secondary backup vault"
  value       = aws_backup_vault.secondary.arn
}

output "tertiary_backup_vault_name" {
  description = "The name of the tertiary backup vault"
  value       = aws_backup_vault.tertiary.name
}

output "tertiary_backup_vault_arn" {
  description = "The ARN of the tertiary backup vault"
  value       = aws_backup_vault.tertiary.arn
}

# ========================================
# KMS Key Information
# ========================================

output "backup_kms_key_primary_id" {
  description = "The ID of the primary region backup KMS key"
  value       = var.enable_backup_encryption ? aws_kms_key.backup_primary.key_id : null
}

output "backup_kms_key_primary_arn" {
  description = "The ARN of the primary region backup KMS key"
  value       = var.enable_backup_encryption ? aws_kms_key.backup_primary.arn : null
}

output "backup_kms_key_secondary_id" {
  description = "The ID of the secondary region backup KMS key"
  value       = var.enable_backup_encryption ? aws_kms_key.backup_secondary.key_id : null
}

output "backup_kms_key_secondary_arn" {
  description = "The ARN of the secondary region backup KMS key"
  value       = var.enable_backup_encryption ? aws_kms_key.backup_secondary.arn : null
}

output "backup_kms_key_tertiary_id" {
  description = "The ID of the tertiary region backup KMS key"
  value       = var.enable_backup_encryption ? aws_kms_key.backup_tertiary.key_id : null
}

output "backup_kms_key_tertiary_arn" {
  description = "The ARN of the tertiary region backup KMS key"
  value       = var.enable_backup_encryption ? aws_kms_key.backup_tertiary.arn : null
}

# ========================================
# IAM Role Information
# ========================================

output "backup_service_role_name" {
  description = "The name of the AWS Backup service role"
  value       = aws_iam_role.backup_service_role.name
}

output "backup_service_role_arn" {
  description = "The ARN of the AWS Backup service role"
  value       = aws_iam_role.backup_service_role.arn
}

output "backup_validator_role_arn" {
  description = "The ARN of the backup validator Lambda role"
  value       = var.enable_backup_validation ? aws_iam_role.backup_validator_role[0].arn : null
}

# ========================================
# SNS and Notification Information
# ========================================

output "backup_notifications_topic_arn" {
  description = "The ARN of the SNS topic for backup notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.backup_notifications[0].arn : null
}

output "backup_notifications_topic_name" {
  description = "The name of the SNS topic for backup notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.backup_notifications[0].name : null
}

# ========================================
# EventBridge Rule Information
# ========================================

output "backup_job_eventbridge_rule_name" {
  description = "The name of the EventBridge rule for backup job monitoring"
  value       = aws_cloudwatch_event_rule.backup_job_state_change.name
}

output "backup_job_eventbridge_rule_arn" {
  description = "The ARN of the EventBridge rule for backup job monitoring"
  value       = aws_cloudwatch_event_rule.backup_job_state_change.arn
}

output "backup_copy_job_eventbridge_rule_name" {
  description = "The name of the EventBridge rule for backup copy job monitoring"
  value       = aws_cloudwatch_event_rule.backup_copy_job_state_change.name
}

output "backup_copy_job_eventbridge_rule_arn" {
  description = "The ARN of the EventBridge rule for backup copy job monitoring"
  value       = aws_cloudwatch_event_rule.backup_copy_job_state_change.arn
}

# ========================================
# Lambda Function Information
# ========================================

output "backup_validator_function_name" {
  description = "The name of the backup validator Lambda function"
  value       = var.enable_backup_validation ? aws_lambda_function.backup_validator[0].function_name : null
}

output "backup_validator_function_arn" {
  description = "The ARN of the backup validator Lambda function"
  value       = var.enable_backup_validation ? aws_lambda_function.backup_validator[0].arn : null
}

# ========================================
# Backup Selection Information
# ========================================

output "backup_selection_id" {
  description = "The ID of the backup selection"
  value       = aws_backup_selection.production_resources.id
}

output "backup_selection_name" {
  description = "The name of the backup selection"
  value       = aws_backup_selection.production_resources.name
}

# ========================================
# Regional Configuration
# ========================================

output "primary_region" {
  description = "The primary AWS region for backup operations"
  value       = var.primary_region
}

output "secondary_region" {
  description = "The secondary AWS region for backup replication"
  value       = var.secondary_region
}

output "tertiary_region" {
  description = "The tertiary AWS region for long-term archival"
  value       = var.tertiary_region
}

# ========================================
# Configuration Summary
# ========================================

output "backup_configuration_summary" {
  description = "Summary of the backup configuration"
  value = {
    backup_plan_name             = aws_backup_plan.multi_region.name
    daily_backup_schedule        = var.daily_backup_schedule
    weekly_backup_schedule       = var.weekly_backup_schedule
    daily_retention_days         = var.daily_retention_days
    weekly_retention_days        = var.weekly_retention_days
    cold_storage_after_days      = var.cold_storage_after_days
    weekly_cold_storage_after_days = var.weekly_cold_storage_after_days
    cross_region_replication    = true
    encryption_enabled          = var.enable_backup_encryption
    notifications_enabled       = var.enable_sns_notifications
    validation_enabled          = var.enable_backup_validation
    backup_resource_tags        = var.backup_resource_tags
  }
}

# ========================================
# Cost Estimation Guidance
# ========================================

output "cost_estimation_notes" {
  description = "Notes for estimating backup costs"
  value = {
    backup_storage_cost_factors = [
      "Number and size of resources being backed up",
      "Backup frequency and retention periods",
      "Cross-region data transfer charges",
      "Cold storage usage after ${var.cold_storage_after_days} days"
    ]
    estimated_monthly_cost_range = "$50-$500 depending on data volume and retention"
    cost_optimization_tips = [
      "Use lifecycle policies to move to cold storage",
      "Adjust retention periods based on compliance requirements",
      "Monitor cross-region transfer costs",
      "Consider backup frequency vs. RPO requirements"
    ]
  }
}

# ========================================
# Next Steps and Commands
# ========================================

output "next_steps" {
  description = "Commands and steps to validate the backup setup"
  value = {
    tag_resources_command = "aws resourcegroupstaggingapi tag-resources --resource-arn-list <resource-arn> --tags BackupEnabled=true,Environment=${var.environment}"
    list_backup_plans     = "aws backup list-backup-plans --region ${var.primary_region}"
    list_backup_jobs      = "aws backup list-backup-jobs --region ${var.primary_region}"
    list_copy_jobs        = "aws backup list-copy-jobs --region ${var.secondary_region}"
    validate_cross_region = "aws backup list-recovery-points --backup-vault-name ${aws_backup_vault.secondary.name} --region ${var.secondary_region}"
  }
}