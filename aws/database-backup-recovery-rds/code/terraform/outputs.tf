# Database Instance Outputs
output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.main.arn
}

output "db_instance_endpoint" {
  description = "The RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_port" {
  description = "The RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_instance_status" {
  description = "The RDS instance status"
  value       = aws_db_instance.main.status
}

output "db_instance_availability_zone" {
  description = "The availability zone of the RDS instance"
  value       = aws_db_instance.main.availability_zone
}

output "db_instance_backup_retention_period" {
  description = "The backup retention period"
  value       = aws_db_instance.main.backup_retention_period
}

output "db_instance_backup_window" {
  description = "The backup window"
  value       = aws_db_instance.main.backup_window
}

output "db_instance_maintenance_window" {
  description = "The maintenance window"
  value       = aws_db_instance.main.maintenance_window
}

output "db_instance_latest_restorable_time" {
  description = "The latest time to which a database can be restored with point-in-time restore"
  value       = aws_db_instance.main.latest_restorable_time
}

# Security Outputs
output "db_security_group_id" {
  description = "The ID of the database security group"
  value       = aws_security_group.rds_sg.id
}

output "db_subnet_group_name" {
  description = "The name of the database subnet group"
  value       = aws_db_subnet_group.rds_subnet_group.name
}

# KMS Key Outputs
output "backup_kms_key_id" {
  description = "The globally unique identifier for the backup encryption key"
  value       = aws_kms_key.backup_key.key_id
}

output "backup_kms_key_arn" {
  description = "The Amazon Resource Name (ARN) of the backup encryption key"
  value       = aws_kms_key.backup_key.arn
}

output "backup_kms_key_alias" {
  description = "The alias of the backup encryption key"
  value       = aws_kms_alias.backup_key_alias.name
}

output "dr_backup_kms_key_id" {
  description = "The globally unique identifier for the DR backup encryption key"
  value       = aws_kms_key.dr_backup_key.key_id
}

output "dr_backup_kms_key_arn" {
  description = "The Amazon Resource Name (ARN) of the DR backup encryption key"
  value       = aws_kms_key.dr_backup_key.arn
}

output "dr_backup_kms_key_alias" {
  description = "The alias of the DR backup encryption key"
  value       = aws_kms_alias.dr_backup_key_alias.name
}

# Backup Configuration Outputs
output "backup_vault_name" {
  description = "The name of the backup vault"
  value       = aws_backup_vault.main.name
}

output "backup_vault_arn" {
  description = "The ARN of the backup vault"
  value       = aws_backup_vault.main.arn
}

output "dr_backup_vault_name" {
  description = "The name of the DR backup vault"
  value       = aws_backup_vault.dr.name
}

output "dr_backup_vault_arn" {
  description = "The ARN of the DR backup vault"
  value       = aws_backup_vault.dr.arn
}

output "backup_plan_id" {
  description = "The ID of the backup plan"
  value       = aws_backup_plan.main.id
}

output "backup_plan_arn" {
  description = "The ARN of the backup plan"
  value       = aws_backup_plan.main.arn
}

output "backup_selection_id" {
  description = "The ID of the backup selection"
  value       = aws_backup_selection.main.id
}

output "backup_role_arn" {
  description = "The ARN of the backup service role"
  value       = aws_iam_role.backup_role.arn
}

# Manual Snapshot Outputs
output "manual_snapshot_id" {
  description = "The ID of the manual snapshot"
  value       = aws_db_snapshot.manual.db_snapshot_identifier
}

output "manual_snapshot_arn" {
  description = "The ARN of the manual snapshot"
  value       = aws_db_snapshot.manual.db_snapshot_arn
}

# Cross-Region Replication Outputs
output "cross_region_replication_enabled" {
  description = "Whether cross-region backup replication is enabled"
  value       = var.enable_cross_region_replication
}

output "cross_region_replication_arn" {
  description = "The ARN of the cross-region automated backup replication"
  value       = var.enable_cross_region_replication ? aws_db_instance_automated_backups_replication.main[0].arn : null
}

# Monitoring and Alerting Outputs
output "backup_notifications_enabled" {
  description = "Whether backup notifications are enabled"
  value       = var.enable_backup_notifications
}

output "sns_topic_arn" {
  description = "The ARN of the SNS topic for backup notifications"
  value       = var.enable_backup_notifications ? aws_sns_topic.backup_notifications[0].arn : null
}

output "backup_failure_alarm_name" {
  description = "The name of the backup failure CloudWatch alarm"
  value       = var.enable_backup_notifications ? aws_cloudwatch_metric_alarm.backup_failures[0].alarm_name : null
}

output "backup_completion_alarm_name" {
  description = "The name of the backup completion CloudWatch alarm"
  value       = var.enable_backup_notifications ? aws_cloudwatch_metric_alarm.backup_completion[0].alarm_name : null
}

# Configuration Summary Outputs
output "configuration_summary" {
  description = "Summary of the backup and recovery configuration"
  value = {
    database = {
      engine                = var.db_engine
      instance_class        = var.db_instance_class
      storage_encrypted     = var.enable_storage_encryption
      deletion_protection   = var.enable_deletion_protection
      backup_retention_days = var.backup_retention_period
      backup_window        = var.backup_window
      maintenance_window   = var.maintenance_window
    }
    backup_strategy = {
      daily_backup_retention_days   = var.daily_backup_retention_days
      weekly_backup_retention_days  = var.weekly_backup_retention_days
      cold_storage_transition_days  = var.cold_storage_transition_days
      cross_region_replication     = var.enable_cross_region_replication
      dr_backup_retention_days     = var.dr_backup_retention_period
      backup_encryption_enabled    = var.enable_backup_encryption
    }
    monitoring = {
      backup_notifications_enabled = var.enable_backup_notifications
      cloudwatch_alarms_enabled   = var.enable_backup_notifications
      performance_insights_enabled = true
      enhanced_monitoring_enabled  = true
    }
  }
}

# Recovery Instructions
output "recovery_instructions" {
  description = "Instructions for performing point-in-time recovery"
  value = {
    point_in_time_recovery = "Use aws rds restore-db-instance-to-point-in-time with source-db-instance-identifier=${aws_db_instance.main.id}"
    snapshot_recovery     = "Use aws rds restore-db-instance-from-db-snapshot with db-snapshot-identifier=${aws_db_snapshot.manual.db_snapshot_identifier}"
    cross_region_recovery = var.enable_cross_region_replication ? "Access backups in ${var.dr_region} region using the DR backup vault" : "Cross-region replication is not enabled"
    backup_vault_access   = "Use AWS Backup console or CLI to access recovery points in vault ${aws_backup_vault.main.name}"
  }
}

# Cost Optimization Recommendations
output "cost_optimization_tips" {
  description = "Cost optimization recommendations for backup strategy"
  value = {
    cold_storage_transition = "Backups transition to cold storage after ${var.cold_storage_transition_days} days for cost savings"
    retention_optimization  = "Consider adjusting retention periods based on compliance requirements"
    cross_region_costs     = var.enable_cross_region_replication ? "Cross-region replication incurs additional storage and data transfer costs" : "Cross-region replication is disabled"
    monitoring_costs       = "CloudWatch logs and alarms incur additional charges"
  }
}

# Security Configuration Summary
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    encryption_at_rest        = var.enable_storage_encryption
    backup_encryption        = var.enable_backup_encryption
    kms_key_rotation_enabled = true
    deletion_protection      = var.enable_deletion_protection
    vpc_security_group       = aws_security_group.rds_sg.id
    private_subnets         = "Database deployed in private subnets"
  }
}

# Compliance Information
output "compliance_features" {
  description = "Features that support compliance requirements"
  value = {
    backup_retention_configurable = "Backup retention period is configurable for compliance needs"
    audit_trail_available        = "CloudTrail integration provides audit trail for all backup operations"
    encryption_in_transit        = "SSL/TLS encryption enforced for database connections"
    access_logging              = "CloudWatch logs capture database access patterns"
    cross_region_dr             = var.enable_cross_region_replication ? "Cross-region disaster recovery capability enabled" : "Cross-region DR not enabled"
  }
}