# Outputs for database performance tuning recipe

# Database Connection Information
output "primary_db_endpoint" {
  description = "Primary database endpoint for connections"
  value       = aws_db_instance.primary.endpoint
  sensitive   = false
}

output "primary_db_port" {
  description = "Primary database port"
  value       = aws_db_instance.primary.port
  sensitive   = false
}

output "primary_db_identifier" {
  description = "Primary database instance identifier"
  value       = aws_db_instance.primary.identifier
  sensitive   = false
}

output "primary_db_name" {
  description = "Primary database name"
  value       = aws_db_instance.primary.db_name
  sensitive   = false
}

output "primary_db_username" {
  description = "Primary database master username"
  value       = aws_db_instance.primary.username
  sensitive   = false
}

output "read_replica_endpoint" {
  description = "Read replica endpoint (if created)"
  value       = var.create_read_replica ? aws_db_instance.read_replica[0].endpoint : null
  sensitive   = false
}

output "read_replica_identifier" {
  description = "Read replica instance identifier (if created)"
  value       = var.create_read_replica ? aws_db_instance.read_replica[0].identifier : null
  sensitive   = false
}

# Database Credentials
output "db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_password.arn
  sensitive   = false
}

output "db_password_secret_name" {
  description = "Name of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_password.name
  sensitive   = false
}

# Parameter Group Information
output "parameter_group_name" {
  description = "Name of the custom parameter group"
  value       = aws_db_parameter_group.postgres_tuned.name
  sensitive   = false
}

output "parameter_group_family" {
  description = "Parameter group family"
  value       = aws_db_parameter_group.postgres_tuned.family
  sensitive   = false
}

# Network Information
output "vpc_id" {
  description = "VPC ID where the database is deployed"
  value       = aws_vpc.main.id
  sensitive   = false
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
  sensitive   = false
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
  sensitive   = false
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
  sensitive   = false
}

output "security_group_id" {
  description = "Security group ID for database access"
  value       = aws_security_group.rds.id
  sensitive   = false
}

# Monitoring Information
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.database_performance.dashboard_name}"
  sensitive   = false
}

output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled"
  value       = aws_db_instance.primary.performance_insights_enabled
  sensitive   = false
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for PostgreSQL logs"
  value       = aws_cloudwatch_log_group.postgresql.name
  sensitive   = false
}

# Performance Monitoring Information
output "cpu_alarm_name" {
  description = "Name of the CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
  sensitive   = false
}

output "connections_alarm_name" {
  description = "Name of the database connections alarm"
  value       = aws_cloudwatch_metric_alarm.high_connections.alarm_name
  sensitive   = false
}

output "read_latency_alarm_name" {
  description = "Name of the read latency alarm"
  value       = aws_cloudwatch_metric_alarm.high_read_latency.alarm_name
  sensitive   = false
}

# Enhanced Monitoring Information
output "monitoring_role_arn" {
  description = "ARN of the RDS monitoring role"
  value       = aws_iam_role.rds_monitoring.arn
  sensitive   = false
}

output "enhanced_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  value       = var.monitoring_interval
  sensitive   = false
}

# Database Configuration Summary
output "tuning_parameters_summary" {
  description = "Summary of key performance tuning parameters applied"
  value = {
    shared_buffers         = "${var.shared_buffers_mb}MB"
    work_mem              = "${var.work_mem_mb}MB"
    maintenance_work_mem  = "${var.maintenance_work_mem_mb}MB"
    effective_cache_size  = "${var.effective_cache_size_gb}GB"
    max_connections       = var.max_connections
    random_page_cost      = var.random_page_cost
    effective_io_concurrency = var.effective_io_concurrency
  }
  sensitive = false
}

# Connection Commands
output "psql_connection_command" {
  description = "Command to connect to the primary database using psql"
  value       = "psql -h ${aws_db_instance.primary.endpoint} -U ${aws_db_instance.primary.username} -d ${aws_db_instance.primary.db_name} -p ${aws_db_instance.primary.port}"
  sensitive   = false
}

output "psql_replica_connection_command" {
  description = "Command to connect to the read replica using psql (if created)"
  value       = var.create_read_replica ? "psql -h ${aws_db_instance.read_replica[0].endpoint} -U ${aws_db_instance.primary.username} -d ${aws_db_instance.primary.db_name} -p ${aws_db_instance.read_replica[0].port}" : null
  sensitive   = false
}

# Resource ARNs for reference
output "primary_db_arn" {
  description = "ARN of the primary database instance"
  value       = aws_db_instance.primary.arn
  sensitive   = false
}

output "read_replica_arn" {
  description = "ARN of the read replica instance (if created)"
  value       = var.create_read_replica ? aws_db_instance.read_replica[0].arn : null
  sensitive   = false
}

output "parameter_group_arn" {
  description = "ARN of the custom parameter group"
  value       = aws_db_parameter_group.postgres_tuned.arn
  sensitive   = false
}

# Resource Tags Information
output "resource_tags" {
  description = "Common tags applied to all resources"
  value = {
    Project      = "Database Performance Tuning"
    Recipe       = "database-performance-tuning-parameter-groups"
    Environment  = var.environment
    ManagedBy    = "terraform"
  }
  sensitive = false
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Notes about cost optimization for the deployed resources"
  value = {
    storage_type               = "gp3 (cost-effective SSD storage)"
    instance_class            = var.db_instance_class
    backup_retention_period   = "${var.db_backup_retention_period} days"
    performance_insights      = "Enabled with ${var.performance_insights_retention_period} days retention"
    enhanced_monitoring       = var.monitoring_interval > 0 ? "Enabled (${var.monitoring_interval}s interval)" : "Disabled"
    read_replica_created      = var.create_read_replica
    deletion_protection       = var.enable_deletion_protection
  }
  sensitive = false
}

# Performance Testing Information
output "performance_testing_notes" {
  description = "Information for conducting performance tests"
  value = {
    endpoint                  = aws_db_instance.primary.endpoint
    port                     = aws_db_instance.primary.port
    database_name            = aws_db_instance.primary.db_name
    performance_insights_url = "https://${data.aws_region.current.name}.console.aws.amazon.com/rds/home?region=${data.aws_region.current.name}#performance-insights-v20206:/resourceId/${aws_db_instance.primary.resource_id}"
    cloudwatch_logs_url      = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.postgresql.name, "/", "$252F")}"
  }
  sensitive = false
}