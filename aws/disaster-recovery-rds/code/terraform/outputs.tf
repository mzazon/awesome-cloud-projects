# Database Information
output "source_database_identifier" {
  description = "Identifier of the source RDS database instance"
  value       = data.aws_db_instance.source.id
}

output "source_database_endpoint" {
  description = "RDS instance endpoint for the source database"
  value       = data.aws_db_instance.source.endpoint
}

output "source_database_port" {
  description = "RDS instance port for the source database"
  value       = data.aws_db_instance.source.port
}

output "source_database_engine" {
  description = "Database engine for the source database"
  value       = data.aws_db_instance.source.engine
}

output "source_database_engine_version" {
  description = "Database engine version for the source database"
  value       = data.aws_db_instance.source.engine_version
}

# Read Replica Information
output "read_replica_identifier" {
  description = "Identifier of the read replica database instance"
  value       = aws_db_instance.read_replica.id
}

output "read_replica_endpoint" {
  description = "RDS instance endpoint for the read replica"
  value       = aws_db_instance.read_replica.endpoint
}

output "read_replica_port" {
  description = "RDS instance port for the read replica"
  value       = aws_db_instance.read_replica.port
}

output "read_replica_arn" {
  description = "ARN of the read replica database instance"
  value       = aws_db_instance.read_replica.arn
}

output "read_replica_region" {
  description = "AWS region where the read replica is deployed"
  value       = var.secondary_region
}

# SNS Topics
output "primary_sns_topic_arn" {
  description = "ARN of the SNS topic in the primary region"
  value       = aws_sns_topic.primary_notifications.arn
}

output "secondary_sns_topic_arn" {
  description = "ARN of the SNS topic in the secondary region"
  value       = aws_sns_topic.secondary_notifications.arn
}

# Lambda Function
output "lambda_function_name" {
  description = "Name of the disaster recovery Lambda function"
  value       = aws_lambda_function.dr_manager.function_name
}

output "lambda_function_arn" {
  description = "ARN of the disaster recovery Lambda function"
  value       = aws_lambda_function.dr_manager.arn
}

# CloudWatch Resources
output "cloudwatch_alarms" {
  description = "CloudWatch alarm names and ARNs"
  value = {
    primary_cpu = {
      name = aws_cloudwatch_metric_alarm.primary_cpu.alarm_name
      arn  = aws_cloudwatch_metric_alarm.primary_cpu.arn
    }
    primary_connections = {
      name = aws_cloudwatch_metric_alarm.primary_connections.alarm_name
      arn  = aws_cloudwatch_metric_alarm.primary_connections.arn
    }
    replica_lag = {
      name = aws_cloudwatch_metric_alarm.replica_lag.alarm_name
      arn  = aws_cloudwatch_metric_alarm.replica_lag.arn
    }
    replica_cpu = {
      name = aws_cloudwatch_metric_alarm.replica_cpu.alarm_name
      arn  = aws_cloudwatch_metric_alarm.replica_cpu.arn
    }
  }
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if created)"
  value = var.create_dashboard ? "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${local.dashboard_name}" : null
}

# IAM Resources
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "rds_enhanced_monitoring_role_arn" {
  description = "ARN of the RDS enhanced monitoring role"
  value       = aws_iam_role.rds_enhanced_monitoring.arn
}

# Resource Names and IDs
output "resource_names" {
  description = "Generated resource names for reference"
  value = {
    replica_name   = local.replica_name
    topic_name     = local.topic_name
    lambda_name    = local.lambda_name
    dashboard_name = local.dashboard_name
    random_suffix  = random_id.suffix.hex
  }
}

# Disaster Recovery Configuration
output "disaster_recovery_config" {
  description = "Disaster recovery configuration summary"
  value = {
    primary_region   = var.primary_region
    secondary_region = var.secondary_region
    source_db        = var.source_db_identifier
    replica_db       = local.replica_name
    multi_az_replica = var.replica_multi_az
    backup_retention = var.backup_retention_period
    monitoring_enabled = true
    notifications_enabled = var.enable_email_notifications
  }
}

# Connection Information
output "connection_instructions" {
  description = "Instructions for connecting to databases"
  value = {
    primary_connection = "mysql -h ${data.aws_db_instance.source.endpoint} -P ${data.aws_db_instance.source.port} -u <username> -p <database_name>"
    replica_connection = "mysql -h ${aws_db_instance.read_replica.endpoint} -P ${aws_db_instance.read_replica.port} -u <username> -p <database_name>"
    failover_promotion = "aws rds promote-read-replica --db-instance-identifier ${local.replica_name} --region ${var.secondary_region}"
  }
}

# Monitoring and Alerting
output "monitoring_configuration" {
  description = "Monitoring and alerting configuration"
  value = {
    cpu_alarm_threshold    = var.cpu_alarm_threshold
    replica_lag_threshold  = var.replica_lag_threshold
    evaluation_periods     = var.alarm_evaluation_periods
    notification_email     = var.notification_email
    lambda_timeout         = var.lambda_timeout
    dashboard_created      = var.create_dashboard
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    storage_encrypted           = var.replica_storage_encrypted
    deletion_protection        = var.enable_deletion_protection
    performance_insights       = var.enable_performance_insights
    enhanced_monitoring        = true
    backup_encrypted           = true
  }
}

# Cost Estimation Information
output "cost_estimation_info" {
  description = "Information for cost estimation"
  value = {
    replica_instance_class = var.replica_instance_class != null ? var.replica_instance_class : data.aws_db_instance.source.instance_class
    multi_az              = var.replica_multi_az
    storage_type          = data.aws_db_instance.source.storage_type
    allocated_storage     = data.aws_db_instance.source.allocated_storage
    backup_retention_days = var.backup_retention_period
    regions               = "${var.primary_region} -> ${var.secondary_region}"
  }
}