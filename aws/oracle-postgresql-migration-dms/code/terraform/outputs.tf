# Output values for Oracle to PostgreSQL database migration infrastructure

#------------------------------------------------------------------------------
# Network Infrastructure Outputs
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC created for migration"
  value       = aws_vpc.migration_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the migration VPC"
  value       = aws_vpc.migration_vpc.cidr_block
}

output "subnet_ids" {
  description = "List of subnet IDs created for migration"
  value       = aws_subnet.migration_subnet[*].id
}

output "security_group_aurora_id" {
  description = "Security group ID for Aurora PostgreSQL"
  value       = aws_security_group.aurora_sg.id
}

output "security_group_dms_id" {
  description = "Security group ID for DMS replication instance"
  value       = aws_security_group.dms_sg.id
}

#------------------------------------------------------------------------------
# Aurora PostgreSQL Outputs
#------------------------------------------------------------------------------

output "aurora_cluster_id" {
  description = "Aurora PostgreSQL cluster identifier"
  value       = aws_rds_cluster.aurora_postgresql.cluster_identifier
}

output "aurora_cluster_endpoint" {
  description = "Aurora PostgreSQL cluster endpoint"
  value       = aws_rds_cluster.aurora_postgresql.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora PostgreSQL cluster reader endpoint"
  value       = aws_rds_cluster.aurora_postgresql.reader_endpoint
}

output "aurora_cluster_port" {
  description = "Aurora PostgreSQL cluster port"
  value       = aws_rds_cluster.aurora_postgresql.port
}

output "aurora_cluster_database_name" {
  description = "Aurora PostgreSQL database name"
  value       = aws_rds_cluster.aurora_postgresql.database_name
}

output "aurora_cluster_master_username" {
  description = "Aurora PostgreSQL master username"
  value       = aws_rds_cluster.aurora_postgresql.master_username
  sensitive   = true
}

output "aurora_cluster_arn" {
  description = "Aurora PostgreSQL cluster ARN"
  value       = aws_rds_cluster.aurora_postgresql.arn
}

output "aurora_instance_id" {
  description = "Aurora PostgreSQL instance identifier"
  value       = aws_rds_cluster_instance.aurora_instance.identifier
}

output "aurora_instance_endpoint" {
  description = "Aurora PostgreSQL instance endpoint"
  value       = aws_rds_cluster_instance.aurora_instance.endpoint
}

#------------------------------------------------------------------------------
# DMS Infrastructure Outputs
#------------------------------------------------------------------------------

output "dms_replication_instance_id" {
  description = "DMS replication instance identifier"
  value       = aws_dms_replication_instance.migration_instance.replication_instance_id
}

output "dms_replication_instance_arn" {
  description = "DMS replication instance ARN"
  value       = aws_dms_replication_instance.migration_instance.replication_instance_arn
}

output "dms_replication_instance_private_ip" {
  description = "DMS replication instance private IP addresses"
  value       = aws_dms_replication_instance.migration_instance.replication_instance_private_ips
}

output "dms_subnet_group_id" {
  description = "DMS replication subnet group identifier"
  value       = aws_dms_replication_subnet_group.dms_subnet_group.id
}

#------------------------------------------------------------------------------
# DMS Endpoint Outputs
#------------------------------------------------------------------------------

output "oracle_source_endpoint_id" {
  description = "Oracle source endpoint identifier"
  value       = aws_dms_endpoint.oracle_source.endpoint_id
}

output "oracle_source_endpoint_arn" {
  description = "Oracle source endpoint ARN"
  value       = aws_dms_endpoint.oracle_source.endpoint_arn
}

output "postgresql_target_endpoint_id" {
  description = "PostgreSQL target endpoint identifier"
  value       = aws_dms_endpoint.postgresql_target.endpoint_id
}

output "postgresql_target_endpoint_arn" {
  description = "PostgreSQL target endpoint ARN"
  value       = aws_dms_endpoint.postgresql_target.endpoint_arn
}

#------------------------------------------------------------------------------
# DMS Task Outputs
#------------------------------------------------------------------------------

output "dms_replication_task_id" {
  description = "DMS replication task identifier"
  value       = aws_dms_replication_task.migration_task.replication_task_id
}

output "dms_replication_task_arn" {
  description = "DMS replication task ARN"
  value       = aws_dms_replication_task.migration_task.replication_task_arn
}

output "migration_type" {
  description = "Type of migration configured"
  value       = aws_dms_replication_task.migration_task.migration_type
}

#------------------------------------------------------------------------------
# IAM Role Outputs
#------------------------------------------------------------------------------

output "dms_vpc_role_arn" {
  description = "DMS VPC management role ARN"
  value       = aws_iam_role.dms_vpc_role.arn
}

output "dms_cloudwatch_logs_role_arn" {
  description = "DMS CloudWatch logs role ARN"
  value       = aws_iam_role.dms_cloudwatch_logs_role.arn
}

output "rds_monitoring_role_arn" {
  description = "RDS enhanced monitoring role ARN"
  value       = aws_iam_role.rds_enhanced_monitoring.arn
}

#------------------------------------------------------------------------------
# Encryption Outputs
#------------------------------------------------------------------------------

output "kms_key_id" {
  description = "KMS key ID for encryption"
  value       = aws_kms_key.migration_kms_key.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN for encryption"
  value       = aws_kms_key.migration_kms_key.arn
}

output "kms_alias_name" {
  description = "KMS key alias name"
  value       = aws_kms_alias.migration_kms_alias.name
}

#------------------------------------------------------------------------------
# Monitoring Outputs
#------------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "SNS topic ARN for DMS alerts"
  value       = var.enable_cloudwatch_alarms ? aws_sns_topic.dms_alerts[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for DMS"
  value       = aws_cloudwatch_log_group.dms_log_group.name
}

output "replication_lag_alarm_name" {
  description = "CloudWatch alarm name for replication lag"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.replication_lag[0].alarm_name : null
}

output "task_failure_alarm_name" {
  description = "CloudWatch alarm name for task failures"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.task_failure[0].alarm_name : null
}

#------------------------------------------------------------------------------
# Connection Information
#------------------------------------------------------------------------------

output "postgresql_connection_string" {
  description = "PostgreSQL connection string (without password)"
  value       = "postgresql://${aws_rds_cluster.aurora_postgresql.master_username}@${aws_rds_cluster.aurora_postgresql.endpoint}:${aws_rds_cluster.aurora_postgresql.port}/${aws_rds_cluster.aurora_postgresql.database_name}"
  sensitive   = true
}

output "psql_connect_command" {
  description = "Command to connect to Aurora PostgreSQL using psql"
  value       = "PGPASSWORD='${var.aurora_master_password}' psql -h ${aws_rds_cluster.aurora_postgresql.endpoint} -U ${aws_rds_cluster.aurora_postgresql.master_username} -d ${aws_rds_cluster.aurora_postgresql.database_name}"
  sensitive   = true
}

#------------------------------------------------------------------------------
# Validation Commands
#------------------------------------------------------------------------------

output "dms_task_status_command" {
  description = "AWS CLI command to check DMS task status"
  value       = "aws dms describe-replication-tasks --replication-task-identifier ${aws_dms_replication_task.migration_task.replication_task_id}"
}

output "dms_table_statistics_command" {
  description = "AWS CLI command to check table migration statistics"
  value       = "aws dms describe-table-statistics --replication-task-arn ${aws_dms_replication_task.migration_task.replication_task_arn}"
}

output "start_migration_command" {
  description = "AWS CLI command to start the migration task"
  value       = "aws dms start-replication-task --replication-task-arn ${aws_dms_replication_task.migration_task.replication_task_arn} --start-replication-task-type start-replication"
}

output "stop_migration_command" {
  description = "AWS CLI command to stop the migration task"
  value       = "aws dms stop-replication-task --replication-task-arn ${aws_dms_replication_task.migration_task.replication_task_arn}"
}

#------------------------------------------------------------------------------
# Project Information
#------------------------------------------------------------------------------

output "project_name" {
  description = "Project name with random suffix"
  value       = local.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}