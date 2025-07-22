# Output Values for PostgreSQL High Availability Cluster
# These outputs provide essential information for connecting to and managing the cluster

# Primary Database Instance Outputs
output "primary_endpoint" {
  description = "RDS instance endpoint for primary database"
  value       = aws_db_instance.postgresql_primary.endpoint
}

output "primary_hosted_zone_id" {
  description = "Hosted zone ID of the RDS instance"
  value       = aws_db_instance.postgresql_primary.hosted_zone_id
}

output "primary_instance_id" {
  description = "RDS instance identifier for primary database"
  value       = aws_db_instance.postgresql_primary.id
}

output "primary_instance_arn" {
  description = "RDS instance ARN for primary database"
  value       = aws_db_instance.postgresql_primary.arn
}

output "primary_instance_resource_id" {
  description = "RDS instance resource ID"
  value       = aws_db_instance.postgresql_primary.resource_id
}

output "primary_engine_version" {
  description = "PostgreSQL engine version of primary instance"
  value       = aws_db_instance.postgresql_primary.engine_version_actual
}

# Read Replica Outputs
output "read_replica_endpoint" {
  description = "RDS read replica endpoint"
  value       = var.create_read_replica ? aws_db_instance.postgresql_read_replica[0].endpoint : null
}

output "read_replica_instance_id" {
  description = "RDS read replica instance identifier"
  value       = var.create_read_replica ? aws_db_instance.postgresql_read_replica[0].id : null
}

output "read_replica_arn" {
  description = "RDS read replica ARN"
  value       = var.create_read_replica ? aws_db_instance.postgresql_read_replica[0].arn : null
}

# Cross-Region Disaster Recovery Outputs
output "dr_replica_endpoint" {
  description = "Cross-region disaster recovery replica endpoint"
  value       = var.create_cross_region_replica ? aws_db_instance.postgresql_dr_replica[0].endpoint : null
}

output "dr_replica_instance_id" {
  description = "Cross-region disaster recovery replica instance identifier"
  value       = var.create_cross_region_replica ? aws_db_instance.postgresql_dr_replica[0].id : null
}

output "dr_replica_arn" {
  description = "Cross-region disaster recovery replica ARN"
  value       = var.create_cross_region_replica ? aws_db_instance.postgresql_dr_replica[0].arn : null
}

output "dr_region" {
  description = "Disaster recovery region"
  value       = var.dr_region
}

# RDS Proxy Outputs
output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for connection pooling"
  value       = var.create_rds_proxy ? aws_db_proxy.postgresql[0].endpoint : null
}

output "rds_proxy_arn" {
  description = "RDS Proxy ARN"
  value       = var.create_rds_proxy ? aws_db_proxy.postgresql[0].arn : null
}

output "rds_proxy_target_endpoint" {
  description = "RDS Proxy target endpoint (read-write)"
  value       = var.create_rds_proxy ? "${aws_db_proxy.postgresql[0].endpoint}:5432" : null
}

# Database Configuration Outputs
output "database_name" {
  description = "Name of the initial database"
  value       = var.db_name
}

output "master_username" {
  description = "Master username for database access"
  value       = var.master_username
  sensitive   = true
}

output "database_port" {
  description = "Database port"
  value       = 5432
}

# Security and Networking Outputs
output "security_group_id" {
  description = "Security group ID for database access"
  value       = aws_security_group.postgresql.id
}

output "security_group_arn" {
  description = "Security group ARN"
  value       = aws_security_group.postgresql.arn
}

output "db_subnet_group_name" {
  description = "Database subnet group name"
  value       = aws_db_subnet_group.postgresql.name
}

output "db_subnet_group_arn" {
  description = "Database subnet group ARN"
  value       = aws_db_subnet_group.postgresql.arn
}

output "vpc_id" {
  description = "VPC ID where resources are deployed"
  value       = data.aws_vpc.selected.id
}

# Backup and Recovery Outputs
output "backup_retention_period" {
  description = "Backup retention period in days"
  value       = aws_db_instance.postgresql_primary.backup_retention_period
}

output "backup_window" {
  description = "Backup window"
  value       = aws_db_instance.postgresql_primary.backup_window
}

output "maintenance_window" {
  description = "Maintenance window"
  value       = aws_db_instance.postgresql_primary.maintenance_window
}

output "latest_restorable_time" {
  description = "Latest restorable time for point-in-time recovery"
  value       = aws_db_instance.postgresql_primary.latest_restorable_time
}

output "initial_snapshot_id" {
  description = "Initial manual snapshot identifier"
  value       = aws_db_snapshot.initial_snapshot.db_snapshot_identifier
}

output "initial_snapshot_arn" {
  description = "Initial manual snapshot ARN"
  value       = aws_db_snapshot.initial_snapshot.db_snapshot_arn
}

# Secrets Manager Outputs
output "credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "credentials_secret_name" {
  description = "Name of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}

# Monitoring Outputs
output "sns_topic_arn" {
  description = "SNS topic ARN for database alerts"
  value       = aws_sns_topic.postgresql_alerts.arn
}

output "cloudwatch_cpu_alarm_arn" {
  description = "CloudWatch CPU utilization alarm ARN"
  value       = aws_cloudwatch_metric_alarm.cpu_high.arn
}

output "cloudwatch_connections_alarm_arn" {
  description = "CloudWatch database connections alarm ARN"
  value       = aws_cloudwatch_metric_alarm.connections_high.arn
}

output "cloudwatch_replica_lag_alarm_arn" {
  description = "CloudWatch read replica lag alarm ARN"
  value       = var.create_read_replica ? aws_cloudwatch_metric_alarm.replica_lag_high[0].arn : null
}

output "rds_event_subscription_arn" {
  description = "RDS event subscription ARN"
  value       = aws_db_event_subscription.postgresql_events.arn
}

# Performance Insights Outputs
output "performance_insights_enabled" {
  description = "Performance Insights enabled status"
  value       = aws_db_instance.postgresql_primary.performance_insights_enabled
}

output "performance_insights_kms_key_id" {
  description = "Performance Insights KMS key ID"
  value       = aws_db_instance.postgresql_primary.performance_insights_kms_key_id
}

# Parameter Group Outputs
output "parameter_group_name" {
  description = "Database parameter group name"
  value       = aws_db_parameter_group.postgresql.name
}

output "parameter_group_arn" {
  description = "Database parameter group ARN"
  value       = aws_db_parameter_group.postgresql.arn
}

# Enhanced Monitoring Outputs
output "monitoring_role_arn" {
  description = "Enhanced monitoring IAM role ARN"
  value       = aws_iam_role.rds_monitoring.arn
}

output "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  value       = aws_db_instance.postgresql_primary.monitoring_interval
}

# Multi-AZ Configuration Outputs
output "multi_az_enabled" {
  description = "Multi-AZ deployment status"
  value       = aws_db_instance.postgresql_primary.multi_az
}

output "availability_zone" {
  description = "Availability zone of the primary instance"
  value       = aws_db_instance.postgresql_primary.availability_zone
}

# Storage Configuration Outputs
output "allocated_storage" {
  description = "Allocated storage in GiB"
  value       = aws_db_instance.postgresql_primary.allocated_storage
}

output "max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling"
  value       = aws_db_instance.postgresql_primary.max_allocated_storage
}

output "storage_type" {
  description = "Storage type"
  value       = aws_db_instance.postgresql_primary.storage_type
}

output "storage_encrypted" {
  description = "Storage encryption status"
  value       = aws_db_instance.postgresql_primary.storage_encrypted
}

output "kms_key_id" {
  description = "KMS key ID for encryption"
  value       = aws_db_instance.postgresql_primary.kms_key_id
}

# Connection Information for Applications
output "connection_strings" {
  description = "Database connection strings for different scenarios"
  value = {
    # Primary connection for read-write operations
    primary = "postgresql://${var.master_username}:<password>@${aws_db_instance.postgresql_primary.endpoint}:5432/${var.db_name}"
    
    # Read replica connection for read-only operations
    read_replica = var.create_read_replica ? "postgresql://${var.master_username}:<password>@${aws_db_instance.postgresql_read_replica[0].endpoint}:5432/${var.db_name}" : null
    
    # RDS Proxy connection for optimized connection pooling
    proxy = var.create_rds_proxy ? "postgresql://${var.master_username}:<password>@${aws_db_proxy.postgresql[0].endpoint}:5432/${var.db_name}" : null
    
    # Disaster recovery connection (cross-region)
    disaster_recovery = var.create_cross_region_replica ? "postgresql://${var.master_username}:<password>@${aws_db_instance.postgresql_dr_replica[0].endpoint}:5432/${var.db_name}" : null
  }
  sensitive = true
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (in USD, approximate)"
  value = {
    primary_instance     = "Approximately $${formatnumber(200, 0)}-$${formatnumber(800, 0)} based on ${var.db_instance_class}"
    read_replica        = var.create_read_replica ? "Approximately $${formatnumber(200, 0)}-$${formatnumber(800, 0)} for read replica" : "No read replica"
    cross_region_replica = var.create_cross_region_replica ? "Approximately $${formatnumber(200, 0)}-$${formatnumber(800, 0)} for DR replica" : "No DR replica"
    storage             = "Approximately $${formatnumber(var.allocated_storage * 0.10, 2)} for ${var.allocated_storage}GB ${var.storage_type} storage"
    backup_storage      = "Backup storage costs depend on backup size and retention period"
    data_transfer       = "Cross-region data transfer charges apply for DR replica"
    note               = "Actual costs may vary based on usage, region, and AWS pricing changes"
  }
}

# Operational Information
output "operational_info" {
  description = "Important operational information"
  value = {
    deletion_protection    = aws_db_instance.postgresql_primary.deletion_protection
    auto_minor_version_upgrade = aws_db_instance.postgresql_primary.auto_minor_version_upgrade
    copy_tags_to_snapshot = aws_db_instance.postgresql_primary.copy_tags_to_snapshot
    cloudwatch_logs_exports = aws_db_instance.postgresql_primary.enabled_cloudwatch_logs_exports
    
    # Important notes for operations team
    notes = [
      "Multi-AZ deployment provides automatic failover capability",
      "Point-in-time recovery available up to ${var.backup_retention_period} days",
      "Performance Insights enabled for query performance monitoring",
      "Enhanced monitoring provides OS-level metrics every ${var.monitoring_interval} seconds",
      "Automated backups occur during ${aws_db_instance.postgresql_primary.backup_window}",
      "Maintenance window scheduled for ${aws_db_instance.postgresql_primary.maintenance_window}",
      var.create_rds_proxy ? "RDS Proxy provides connection pooling and improved failover handling" : "No RDS Proxy configured",
      var.create_cross_region_replica ? "Cross-region replica available in ${var.dr_region} for disaster recovery" : "No cross-region disaster recovery configured"
    ]
  }
}