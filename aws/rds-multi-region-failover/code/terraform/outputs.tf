# Output values for RDS Multi-AZ Cross-Region Failover infrastructure
# These outputs provide essential information for connecting to and managing the database infrastructure

# === PRIMARY DATABASE OUTPUTS ===

output "primary_db_instance_id" {
  description = "The RDS instance identifier for the primary database"
  value       = aws_db_instance.primary.id
}

output "primary_db_endpoint" {
  description = "The RDS instance endpoint for the primary database"
  value       = aws_db_instance.primary.endpoint
}

output "primary_db_port" {
  description = "The database port for the primary instance"
  value       = aws_db_instance.primary.port
}

output "primary_db_arn" {
  description = "The ARN of the RDS primary instance"
  value       = aws_db_instance.primary.arn
}

output "primary_db_hosted_zone_id" {
  description = "The canonical hosted zone ID of the DB instance"
  value       = aws_db_instance.primary.hosted_zone_id
}

output "primary_db_availability_zone" {
  description = "The availability zone of the primary instance"
  value       = aws_db_instance.primary.availability_zone
}

output "primary_db_multi_az" {
  description = "If the RDS instance is multi AZ enabled"
  value       = aws_db_instance.primary.multi_az
}

# === SECONDARY DATABASE OUTPUTS ===

output "replica_db_instance_id" {
  description = "The RDS instance identifier for the read replica"
  value       = aws_db_instance.replica.id
}

output "replica_db_endpoint" {
  description = "The RDS instance endpoint for the read replica"
  value       = aws_db_instance.replica.endpoint
}

output "replica_db_port" {
  description = "The database port for the replica instance"
  value       = aws_db_instance.replica.port
}

output "replica_db_arn" {
  description = "The ARN of the RDS replica instance"
  value       = aws_db_instance.replica.arn
}

output "replica_db_availability_zone" {
  description = "The availability zone of the replica instance"
  value       = aws_db_instance.replica.availability_zone
}

# === DNS AND FAILOVER OUTPUTS ===

output "route53_zone_id" {
  description = "The Route 53 hosted zone ID for database DNS"
  value       = aws_route53_zone.database.zone_id
}

output "route53_zone_name" {
  description = "The Route 53 hosted zone name"
  value       = aws_route53_zone.database.name
}

output "database_dns_name" {
  description = "The DNS name for database connections (with failover)"
  value       = "${var.dns_record_name}.${var.route53_hosted_zone_name}"
}

output "primary_health_check_id" {
  description = "The Route 53 health check ID for the primary database"
  value       = aws_route53_health_check.primary_db.id
}

# === SECURITY OUTPUTS ===

output "primary_security_group_id" {
  description = "The security group ID for the primary database"
  value       = aws_security_group.rds_primary.id
}

output "secondary_security_group_id" {
  description = "The security group ID for the secondary database"
  value       = aws_security_group.rds_secondary.id
}

output "db_parameter_group_name" {
  description = "The name of the DB parameter group"
  value       = aws_db_parameter_group.financial_db.name
}

output "primary_subnet_group_name" {
  description = "The name of the DB subnet group in primary region"
  value       = aws_db_subnet_group.primary.name
}

output "secondary_subnet_group_name" {
  description = "The name of the DB subnet group in secondary region"
  value       = aws_db_subnet_group.secondary.name
}

# === SECRETS MANAGER OUTPUTS ===

output "db_password_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the database password"
  value       = aws_secretsmanager_secret.db_password.arn
  sensitive   = true
}

output "db_password_secret_name" {
  description = "The name of the Secrets Manager secret containing the database password"
  value       = aws_secretsmanager_secret.db_password.name
}

# === MONITORING OUTPUTS ===

output "rds_monitoring_role_arn" {
  description = "The ARN of the IAM role for RDS enhanced monitoring in primary region"
  value       = aws_iam_role.rds_monitoring.arn
}

output "rds_monitoring_role_arn_secondary" {
  description = "The ARN of the IAM role for RDS enhanced monitoring in secondary region"
  value       = aws_iam_role.rds_monitoring_secondary.arn
}

output "sns_topic_arn_primary" {
  description = "The ARN of the SNS topic for database alerts in primary region"
  value       = aws_sns_topic.db_alerts_primary.arn
}

output "sns_topic_arn_secondary" {
  description = "The ARN of the SNS topic for database alerts in secondary region"
  value       = aws_sns_topic.db_alerts_secondary.arn
}

# === CLOUDWATCH ALARMS OUTPUTS ===

output "connection_failures_alarm_name" {
  description = "The name of the CloudWatch alarm for connection failures"
  value       = aws_cloudwatch_metric_alarm.primary_connection_failures.alarm_name
}

output "replica_lag_alarm_name" {
  description = "The name of the CloudWatch alarm for replica lag"
  value       = aws_cloudwatch_metric_alarm.replica_lag.alarm_name
}

output "cpu_utilization_alarm_name" {
  description = "The name of the CloudWatch alarm for CPU utilization"
  value       = aws_cloudwatch_metric_alarm.primary_cpu_utilization.alarm_name
}

# === BACKUP OUTPUTS ===

output "automated_backup_replication_arn" {
  description = "The ARN of the automated backup replication (if enabled)"
  value       = var.enable_automated_backup_replication ? aws_db_instance_automated_backups_replication.replica[0].arn : null
}

# === PROMOTION ROLE OUTPUTS ===

output "rds_promotion_role_arn" {
  description = "The ARN of the IAM role for RDS promotion automation"
  value       = aws_iam_role.rds_promotion_role.arn
}

# === CLOUDWATCH LOGS OUTPUTS ===

output "primary_db_log_group_name" {
  description = "The name of the CloudWatch log group for primary database logs"
  value       = aws_cloudwatch_log_group.rds_postgresql_primary.name
}

output "secondary_db_log_group_name" {
  description = "The name of the CloudWatch log group for secondary database logs"
  value       = aws_cloudwatch_log_group.rds_postgresql_secondary.name
}

# === DATABASE CONNECTION INFORMATION ===

output "database_connection_info" {
  description = "Database connection information summary"
  value = {
    primary_endpoint   = aws_db_instance.primary.endpoint
    replica_endpoint   = aws_db_instance.replica.endpoint
    failover_dns_name  = "${var.dns_record_name}.${var.route53_hosted_zone_name}"
    database_name      = aws_db_instance.primary.db_name
    master_username    = aws_db_instance.primary.username
    port              = aws_db_instance.primary.port
    engine            = aws_db_instance.primary.engine
    engine_version    = aws_db_instance.primary.engine_version
  }
}

# === REGIONAL INFORMATION ===

output "deployment_regions" {
  description = "Information about the deployment regions"
  value = {
    primary_region   = data.aws_region.primary.name
    secondary_region = data.aws_region.secondary.name
    account_id       = data.aws_caller_identity.current.account_id
  }
}

# === RESOURCE IDENTIFIERS ===

output "resource_identifiers" {
  description = "Unique identifiers for created resources"
  value = {
    random_suffix           = random_id.suffix.hex
    primary_db_identifier   = aws_db_instance.primary.id
    replica_db_identifier   = aws_db_instance.replica.id
    parameter_group_name    = aws_db_parameter_group.financial_db.name
    hosted_zone_id         = aws_route53_zone.database.zone_id
  }
}

# === TERRAFORM STATE INFORMATION ===

output "terraform_state_info" {
  description = "Information about the Terraform deployment"
  value = {
    aws_provider_version = "~> 5.0"
    terraform_version    = ">= 1.0"
    deployment_timestamp = timestamp()
    resource_count = {
      rds_instances     = 2
      security_groups   = 2
      subnet_groups     = 2
      cloudwatch_alarms = 3
      sns_topics       = 2
      route53_records  = 2
    }
  }
}