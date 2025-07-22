# Outputs for Aurora Serverless v2 Database Scaling Infrastructure
# These outputs provide essential information for connecting to and monitoring the Aurora cluster

# Cluster Information
output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.aurora_serverless.cluster_identifier
}

output "cluster_arn" {
  description = "Amazon Resource Name (ARN) of Aurora cluster"
  value       = aws_rds_cluster.aurora_serverless.arn
}

output "cluster_resource_id" {
  description = "Aurora cluster resource ID"
  value       = aws_rds_cluster.aurora_serverless.cluster_resource_id
}

output "engine" {
  description = "Aurora cluster engine"
  value       = aws_rds_cluster.aurora_serverless.engine
}

output "engine_version" {
  description = "Aurora cluster engine version"
  value       = aws_rds_cluster.aurora_serverless.engine_version_actual
}

# Connection Endpoints
output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.aurora_serverless.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.aurora_serverless.reader_endpoint
}

output "cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.aurora_serverless.port
}

# Database Configuration
output "database_name" {
  description = "Name of the initial database created"
  value       = aws_rds_cluster.aurora_serverless.database_name
}

output "master_username" {
  description = "Aurora cluster master username"
  value       = aws_rds_cluster.aurora_serverless.master_username
  sensitive   = true
}

# Serverless v2 Scaling Configuration
output "serverless_min_capacity" {
  description = "Minimum Aurora Capacity Units (ACUs) configured"
  value       = var.serverless_min_capacity
}

output "serverless_max_capacity" {
  description = "Maximum Aurora Capacity Units (ACUs) configured"
  value       = var.serverless_max_capacity
}

# Instance Information
output "writer_instance_identifier" {
  description = "Aurora writer instance identifier"
  value       = aws_rds_cluster_instance.aurora_writer.identifier
}

output "writer_instance_endpoint" {
  description = "Aurora writer instance endpoint"
  value       = aws_rds_cluster_instance.aurora_writer.endpoint
}

output "reader_instance_identifier" {
  description = "Aurora reader instance identifier (if created)"
  value       = var.create_read_replica ? aws_rds_cluster_instance.aurora_reader[0].identifier : null
}

output "reader_instance_endpoint" {
  description = "Aurora reader instance endpoint (if created)"
  value       = var.create_read_replica ? aws_rds_cluster_instance.aurora_reader[0].endpoint : null
}

# Network Configuration
output "vpc_id" {
  description = "ID of the VPC where Aurora cluster is deployed"
  value       = var.use_existing_vpc ? var.existing_vpc_id : aws_vpc.aurora_vpc[0].id
}

output "subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.aurora_subnet_group.name
}

output "security_group_id" {
  description = "ID of the security group attached to Aurora cluster"
  value       = aws_security_group.aurora_sg.id
}

output "subnet_ids" {
  description = "List of subnet IDs used by Aurora cluster"
  value       = var.use_existing_vpc ? var.existing_subnet_ids : aws_subnet.aurora_private[*].id
}

# Monitoring and Logging
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups created for Aurora logs"
  value = {
    error_log     = var.enable_cloudwatch_logs && contains(var.enabled_cloudwatch_logs_exports, "error") ? aws_cloudwatch_log_group.aurora_error_log[0].name : null
    general_log   = var.enable_cloudwatch_logs && contains(var.enabled_cloudwatch_logs_exports, "general") ? aws_cloudwatch_log_group.aurora_general_log[0].name : null
    slowquery_log = var.enable_cloudwatch_logs && contains(var.enabled_cloudwatch_logs_exports, "slowquery") ? aws_cloudwatch_log_group.aurora_slowquery_log[0].name : null
  }
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring"
  value = var.enable_cloudwatch_alarms ? {
    high_acu_alarm    = aws_cloudwatch_metric_alarm.aurora_high_acu[0].alarm_name
    low_acu_alarm     = aws_cloudwatch_metric_alarm.aurora_low_acu[0].alarm_name
    connections_alarm = aws_cloudwatch_metric_alarm.aurora_connections[0].alarm_name
  } : {}
}

output "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
  value       = var.enable_cloudwatch_alarms && var.alarm_notification_email != null ? aws_sns_topic.aurora_alerts[0].arn : null
}

# Parameter Groups
output "cluster_parameter_group_name" {
  description = "Name of the custom cluster parameter group"
  value       = aws_rds_cluster_parameter_group.aurora_params.name
}

# IAM Roles
output "monitoring_role_arn" {
  description = "ARN of the IAM role for RDS enhanced monitoring"
  value       = aws_iam_role.rds_enhanced_monitoring.arn
}

# Backup Configuration
output "backup_retention_period" {
  description = "Number of days automated backups are retained"
  value       = aws_rds_cluster.aurora_serverless.backup_retention_period
}

output "backup_window" {
  description = "Daily time range during which automated backups are created"
  value       = aws_rds_cluster.aurora_serverless.preferred_backup_window
}

output "maintenance_window" {
  description = "Weekly time range during which system maintenance can occur"
  value       = aws_rds_cluster.aurora_serverless.preferred_maintenance_window
}

# Connection Information for Applications
output "connection_info" {
  description = "Complete connection information for applications"
  value = {
    writer_endpoint = aws_rds_cluster.aurora_serverless.endpoint
    reader_endpoint = aws_rds_cluster.aurora_serverless.reader_endpoint
    port           = aws_rds_cluster.aurora_serverless.port
    database_name  = aws_rds_cluster.aurora_serverless.database_name
    username       = aws_rds_cluster.aurora_serverless.master_username
  }
  sensitive = true
}

# Connection Strings for Different Use Cases
output "mysql_connection_string" {
  description = "MySQL connection string for applications (password not included)"
  value       = "mysql://${aws_rds_cluster.aurora_serverless.master_username}@${aws_rds_cluster.aurora_serverless.endpoint}:${aws_rds_cluster.aurora_serverless.port}/${aws_rds_cluster.aurora_serverless.database_name}"
  sensitive   = true
}

output "jdbc_connection_string" {
  description = "JDBC connection string for Java applications (password not included)"
  value       = "jdbc:mysql://${aws_rds_cluster.aurora_serverless.endpoint}:${aws_rds_cluster.aurora_serverless.port}/${aws_rds_cluster.aurora_serverless.database_name}"
}

# Monitoring URLs
output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard for Aurora monitoring"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=Aurora-${aws_rds_cluster.aurora_serverless.cluster_identifier}"
}

output "performance_insights_url" {
  description = "URL to Performance Insights for database performance monitoring"
  value       = var.enable_performance_insights ? "https://${var.aws_region}.console.aws.amazon.com/rds/home?region=${var.aws_region}#performance-insights-v20206:/database/${aws_rds_cluster_instance.aurora_writer.resource_id}/overview" : null
}

# Cost Monitoring
output "estimated_monthly_cost_range" {
  description = "Estimated monthly cost range based on ACU configuration (USD)"
  value = {
    minimum = "${var.serverless_min_capacity * 24 * 30 * 0.90} - ${var.serverless_max_capacity * 24 * 30 * 0.90}"
    note    = "Cost per ACU-hour is approximately $0.90. Actual costs vary based on usage patterns."
  }
}

# Security Information
output "encryption_enabled" {
  description = "Whether storage encryption is enabled"
  value       = aws_rds_cluster.aurora_serverless.storage_encrypted
}

output "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled"
  value       = aws_rds_cluster.aurora_serverless.deletion_protection
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for connecting to and using the Aurora cluster"
  value = {
    connect_via_mysql_client = "mysql -h ${aws_rds_cluster.aurora_serverless.endpoint} -P ${aws_rds_cluster.aurora_serverless.port} -u ${aws_rds_cluster.aurora_serverless.master_username} -p ${aws_rds_cluster.aurora_serverless.database_name}"
    monitor_acu_usage       = "aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name ServerlessDatabaseCapacity --dimensions Name=DBClusterIdentifier,Value=${aws_rds_cluster.aurora_serverless.cluster_identifier} --start-time $(date -u -d '1 hour ago' +%%Y-%%m-%%dT%%H:%%M:%%S) --end-time $(date -u +%%Y-%%m-%%dT%%H:%%M:%%S) --period 300 --statistics Average"
    scaling_configuration   = "Min: ${var.serverless_min_capacity} ACUs, Max: ${var.serverless_max_capacity} ACUs"
  }
}