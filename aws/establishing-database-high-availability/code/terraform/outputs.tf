# outputs.tf - Output values for Multi-AZ Database Deployment

# Cluster Information
output "cluster_identifier" {
  description = "RDS cluster identifier"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "cluster_arn" {
  description = "Amazon Resource Name (ARN) of the RDS cluster"
  value       = aws_rds_cluster.main.arn
}

output "cluster_resource_id" {
  description = "RDS cluster resource ID"
  value       = aws_rds_cluster.main.cluster_resource_id
}

output "cluster_hosted_zone_id" {
  description = "Route53 Hosted Zone ID of the cluster endpoint"
  value       = aws_rds_cluster.main.hosted_zone_id
}

# Database Connection Information
output "writer_endpoint" {
  description = "Writer endpoint for the RDS cluster"
  value       = aws_rds_cluster.main.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint for the RDS cluster"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "database_name" {
  description = "Name of the database"
  value       = aws_rds_cluster.main.database_name
}

output "database_port" {
  description = "Port on which the database accepts connections"
  value       = aws_rds_cluster.main.port
}

output "master_username" {
  description = "Master username for the database"
  value       = aws_rds_cluster.main.master_username
  sensitive   = true
}

# Engine Information
output "engine" {
  description = "Database engine"
  value       = aws_rds_cluster.main.engine
}

output "engine_version" {
  description = "Database engine version"
  value       = aws_rds_cluster.main.engine_version_actual
}

# Instance Information
output "cluster_instances" {
  description = "List of RDS cluster instance identifiers"
  value = [
    aws_rds_cluster_instance.writer.identifier,
    aws_rds_cluster_instance.reader_1.identifier,
    aws_rds_cluster_instance.reader_2.identifier
  ]
}

output "writer_instance_endpoint" {
  description = "Writer instance endpoint"
  value       = aws_rds_cluster_instance.writer.endpoint
}

output "reader_instance_endpoints" {
  description = "Reader instance endpoints"
  value = [
    aws_rds_cluster_instance.reader_1.endpoint,
    aws_rds_cluster_instance.reader_2.endpoint
  ]
}

# Security and Network Information
output "security_group_id" {
  description = "ID of the RDS cluster security group"
  value       = aws_security_group.rds_cluster.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.rds_cluster.name
}

output "availability_zones" {
  description = "List of availability zones used by the cluster"
  value       = aws_rds_cluster.main.availability_zones
}

# Parameter Store Information
output "parameter_store_paths" {
  description = "AWS Systems Manager Parameter Store paths for database configuration"
  value = {
    master_password  = aws_ssm_parameter.db_password.name
    master_username  = aws_ssm_parameter.db_username.name
    writer_endpoint  = aws_ssm_parameter.writer_endpoint.name
    reader_endpoint  = aws_ssm_parameter.reader_endpoint.name
  }
}

# Encryption Information
output "storage_encrypted" {
  description = "Whether the cluster storage is encrypted"
  value       = aws_rds_cluster.main.storage_encrypted
}

output "kms_key_id" {
  description = "KMS key ID used for encryption (if encryption is enabled)"
  value       = var.enable_storage_encryption ? aws_kms_key.rds_encryption[0].key_id : null
}

# Backup Information
output "backup_retention_period" {
  description = "Backup retention period in days"
  value       = aws_rds_cluster.main.backup_retention_period
}

output "preferred_backup_window" {
  description = "Preferred backup window"
  value       = aws_rds_cluster.main.preferred_backup_window
}

output "preferred_maintenance_window" {
  description = "Preferred maintenance window"
  value       = aws_rds_cluster.main.preferred_maintenance_window
}

# Monitoring Information
output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled for cluster instances"
  value       = var.enable_performance_insights
}

output "monitoring_role_arn" {
  description = "IAM role ARN for enhanced monitoring"
  value       = aws_iam_role.rds_monitoring.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.rds_monitoring.dashboard_name}"
}

# SNS Information (if created)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for database alerts"
  value       = var.create_sns_topic ? aws_sns_topic.db_alerts[0].arn : null
}

# CloudWatch Alarm Information
output "cloudwatch_alarms" {
  description = "CloudWatch alarm ARNs for database monitoring"
  value = {
    high_cpu_alarm         = aws_cloudwatch_metric_alarm.high_cpu.arn
    high_connections_alarm = aws_cloudwatch_metric_alarm.high_connections.arn
  }
}

# Connection String Examples
output "connection_examples" {
  description = "Example connection strings for different programming languages"
  value = {
    postgresql_psql = var.db_engine == "aurora-postgresql" ? "psql -h ${aws_rds_cluster.main.endpoint} -U ${var.db_master_username} -d ${var.db_name}" : null
    postgresql_python = var.db_engine == "aurora-postgresql" ? "postgresql://${var.db_master_username}:<password>@${aws_rds_cluster.main.endpoint}:${aws_rds_cluster.main.port}/${var.db_name}" : null
    mysql_cli = var.db_engine == "aurora-mysql" ? "mysql -h ${aws_rds_cluster.main.endpoint} -u ${var.db_master_username} -p ${var.db_name}" : null
    mysql_python = var.db_engine == "aurora-mysql" ? "mysql://${var.db_master_username}:<password>@${aws_rds_cluster.main.endpoint}:${aws_rds_cluster.main.port}/${var.db_name}" : null
  }
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (approximate)"
  value = {
    note = "These are rough estimates and actual costs may vary based on usage patterns, data transfer, and current AWS pricing"
    instances = "3x ${var.db_instance_class} instances (~$200-800/month depending on instance type)"
    storage = "Aurora storage is pay-per-use (~$0.10/GB/month)"
    backup_storage = "Backup storage beyond retention period (~$0.021/GB/month)"
    data_transfer = "Cross-AZ data transfer for replication (~$0.01/GB)"
  }
}

# High Availability Information
output "high_availability_info" {
  description = "High availability configuration details"
  value = {
    multi_az_deployment = "Yes - Aurora Multi-AZ cluster with automatic failover"
    failover_time = "Typically less than 35 seconds with Aurora Multi-AZ clusters"
    availability_zones = length(local.availability_zones)
    replication_type = "Semisynchronous replication for data consistency"
    automatic_failover = "Enabled - RDS manages failover automatically"
    backup_strategy = "Automated daily backups with ${var.backup_retention_period}-day retention"
  }
}

# Best Practices Information
output "operational_best_practices" {
  description = "Operational best practices and recommendations"
  value = {
    connection_pooling = "Implement connection pooling in your applications for better performance"
    read_scaling = "Use reader endpoint for read-only queries to distribute load"
    monitoring = "Monitor CPU, connections, and I/O metrics via CloudWatch dashboard"
    security = "Database password stored securely in AWS Systems Manager Parameter Store"
    maintenance = "Maintenance window scheduled for ${var.preferred_maintenance_window}"
    backup_testing = "Regularly test backup restoration procedures"
    performance_insights = var.enable_performance_insights ? "Performance Insights enabled for query analysis" : "Consider enabling Performance Insights for detailed performance monitoring"
  }
}