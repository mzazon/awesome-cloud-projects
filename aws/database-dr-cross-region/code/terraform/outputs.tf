# Output values for database disaster recovery infrastructure

# ============================================================================
# DATABASE OUTPUTS
# ============================================================================

output "primary_db_identifier" {
  description = "Identifier of the primary RDS database instance"
  value       = aws_db_instance.primary.identifier
}

output "primary_db_endpoint" {
  description = "RDS instance endpoint for the primary database"
  value       = aws_db_instance.primary.endpoint
}

output "primary_db_port" {
  description = "RDS instance port for the primary database"
  value       = aws_db_instance.primary.port
}

output "primary_db_arn" {
  description = "ARN of the primary RDS database instance"
  value       = aws_db_instance.primary.arn
}

output "replica_db_identifier" {
  description = "Identifier of the read replica database instance"
  value       = aws_db_instance.read_replica.identifier
}

output "replica_db_endpoint" {
  description = "RDS instance endpoint for the read replica"
  value       = aws_db_instance.read_replica.endpoint
}

output "replica_db_port" {
  description = "RDS instance port for the read replica"
  value       = aws_db_instance.read_replica.port
}

output "replica_db_arn" {
  description = "ARN of the read replica database instance"
  value       = aws_db_instance.read_replica.arn
}

# ============================================================================
# REGION AND ACCOUNT OUTPUTS
# ============================================================================

output "primary_region" {
  description = "Primary AWS region"
  value       = var.primary_region
}

output "dr_region" {
  description = "Disaster recovery AWS region"
  value       = var.dr_region
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# NETWORKING OUTPUTS
# ============================================================================

output "primary_vpc_id" {
  description = "VPC ID in the primary region"
  value       = data.aws_vpc.primary.id
}

output "dr_vpc_id" {
  description = "VPC ID in the DR region"
  value       = data.aws_vpc.dr.id
}

output "primary_db_subnet_group" {
  description = "DB subnet group name in the primary region"
  value       = aws_db_subnet_group.primary.name
}

output "dr_db_subnet_group" {
  description = "DB subnet group name in the DR region"
  value       = aws_db_subnet_group.dr.name
}

output "primary_security_group_id" {
  description = "Security group ID for the primary database"
  value       = aws_security_group.primary_db.id
}

output "dr_security_group_id" {
  description = "Security group ID for the DR database"
  value       = aws_security_group.dr_db.id
}

# ============================================================================
# SNS TOPIC OUTPUTS
# ============================================================================

output "primary_sns_topic_arn" {
  description = "ARN of the SNS topic in the primary region"
  value       = aws_sns_topic.primary_alerts.arn
}

output "dr_sns_topic_arn" {
  description = "ARN of the SNS topic in the DR region"
  value       = aws_sns_topic.dr_alerts.arn
}

output "primary_sns_topic_name" {
  description = "Name of the SNS topic in the primary region"
  value       = aws_sns_topic.primary_alerts.name
}

output "dr_sns_topic_name" {
  description = "Name of the SNS topic in the DR region"
  value       = aws_sns_topic.dr_alerts.name
}

# ============================================================================
# CLOUDWATCH ALARM OUTPUTS
# ============================================================================

output "primary_db_connection_alarm_name" {
  description = "Name of the primary database connection failure alarm"
  value       = aws_cloudwatch_metric_alarm.primary_db_connection_failure.alarm_name
}

output "primary_db_cpu_alarm_name" {
  description = "Name of the primary database CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.primary_db_cpu.alarm_name
}

output "replica_lag_alarm_name" {
  description = "Name of the replica lag alarm"
  value       = aws_cloudwatch_metric_alarm.replica_lag.alarm_name
}

output "dr_db_cpu_alarm_name" {
  description = "Name of the DR database CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.dr_db_cpu.alarm_name
}

# ============================================================================
# ROUTE 53 HEALTH CHECK OUTPUTS
# ============================================================================

output "primary_health_check_id" {
  description = "ID of the Route 53 health check for the primary database"
  value       = var.create_health_checks ? aws_route53_health_check.primary_db[0].id : null
}

output "dr_health_check_id" {
  description = "ID of the Route 53 health check for the DR database"
  value       = var.create_health_checks ? aws_route53_health_check.dr_db[0].id : null
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "dr_coordinator_function_name" {
  description = "Name of the DR coordinator Lambda function"
  value       = aws_lambda_function.dr_coordinator.function_name
}

output "dr_coordinator_function_arn" {
  description = "ARN of the DR coordinator Lambda function"
  value       = aws_lambda_function.dr_coordinator.arn
}

output "replica_promoter_function_name" {
  description = "Name of the replica promoter Lambda function"
  value       = aws_lambda_function.replica_promoter.function_name
}

output "replica_promoter_function_arn" {
  description = "ARN of the replica promoter Lambda function"
  value       = aws_lambda_function.replica_promoter.arn
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "rds_monitoring_role_arn" {
  description = "ARN of the RDS monitoring role in the primary region"
  value       = aws_iam_role.rds_monitoring_role.arn
}

output "rds_monitoring_role_dr_arn" {
  description = "ARN of the RDS monitoring role in the DR region"
  value       = aws_iam_role.rds_monitoring_role_dr.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role in the primary region"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_dr_arn" {
  description = "ARN of the Lambda execution role in the DR region"
  value       = aws_iam_role.lambda_execution_role_dr.arn
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "dr_config_bucket_name" {
  description = "Name of the S3 bucket for DR configuration"
  value       = aws_s3_bucket.dr_config.bucket
}

output "dr_config_bucket_arn" {
  description = "ARN of the S3 bucket for DR configuration"
  value       = aws_s3_bucket.dr_config.arn
}

output "dr_runbook_s3_key" {
  description = "S3 key for the disaster recovery runbook"
  value       = aws_s3_object.dr_runbook.key
}

# ============================================================================
# SYSTEMS MANAGER PARAMETER OUTPUTS
# ============================================================================

output "dr_config_parameter_name" {
  description = "Name of the Systems Manager parameter containing DR configuration"
  value       = aws_ssm_parameter.dr_config.name
}

output "dr_status_parameter_name" {
  description = "Name of the Systems Manager parameter containing DR status"
  value       = aws_ssm_parameter.dr_status.name
}

# ============================================================================
# EVENTBRIDGE OUTPUTS
# ============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for RDS promotion events"
  value       = var.enable_eventbridge_rules ? aws_cloudwatch_event_rule.rds_promotion_events[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for RDS promotion events"
  value       = var.enable_eventbridge_rules ? aws_cloudwatch_event_rule.rds_promotion_events[0].arn : null
}

# ============================================================================
# PARAMETER GROUP OUTPUTS
# ============================================================================

output "custom_parameter_group_name" {
  description = "Name of the custom parameter group optimized for replication"
  value       = var.create_custom_parameter_group ? aws_db_parameter_group.mysql_replication_optimized[0].name : null
}

output "custom_parameter_group_arn" {
  description = "ARN of the custom parameter group optimized for replication"
  value       = var.create_custom_parameter_group ? aws_db_parameter_group.mysql_replication_optimized[0].arn : null
}

# ============================================================================
# RESOURCE TAGS OUTPUTS
# ============================================================================

output "common_tags" {
  description = "Common tags applied to all resources"
  value = merge({
    Project     = "DatabaseDisasterRecovery"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "database-disaster-recovery-cross-region-read-replicas"
  }, var.additional_tags)
}

# ============================================================================
# MONITORING AND ALERTING CONFIGURATION OUTPUTS
# ============================================================================

output "monitoring_configuration" {
  description = "Summary of monitoring and alerting configuration"
  value = {
    cpu_threshold              = var.cpu_threshold
    replica_lag_threshold      = var.replica_lag_threshold
    connection_failure_threshold = var.connection_failure_threshold
    monitoring_interval        = var.monitoring_interval
    performance_insights_enabled = var.enable_performance_insights
    notification_email         = var.notification_email != "" ? "configured" : "not_configured"
  }
}

# ============================================================================
# DISASTER RECOVERY CONFIGURATION SUMMARY
# ============================================================================

output "disaster_recovery_summary" {
  description = "Summary of the disaster recovery configuration"
  value = {
    primary_database = {
      identifier = aws_db_instance.primary.identifier
      endpoint   = aws_db_instance.primary.endpoint
      region     = var.primary_region
      engine     = var.db_engine
      instance_class = var.db_instance_class
    }
    replica_database = {
      identifier = aws_db_instance.read_replica.identifier
      endpoint   = aws_db_instance.read_replica.endpoint
      region     = var.dr_region
      engine     = var.db_engine
      instance_class = var.db_instance_class
    }
    automation = {
      dr_coordinator_function = aws_lambda_function.dr_coordinator.function_name
      replica_promoter_function = aws_lambda_function.replica_promoter.function_name
      eventbridge_automation = var.enable_eventbridge_rules
      health_checks_enabled = var.create_health_checks
    }
    storage = {
      config_bucket = aws_s3_bucket.dr_config.bucket
      runbook_location = "s3://${aws_s3_bucket.dr_config.bucket}/${aws_s3_object.dr_runbook.key}"
      parameter_store_config = aws_ssm_parameter.dr_config.name
    }
  }
  sensitive = false
}

# ============================================================================
# CONNECTION INFORMATION FOR APPLICATIONS
# ============================================================================

output "application_connection_info" {
  description = "Connection information for applications"
  value = {
    primary_connection = {
      endpoint = aws_db_instance.primary.endpoint
      port     = aws_db_instance.primary.port
      username = aws_db_instance.primary.username
      database_name = aws_db_instance.primary.db_name
    }
    replica_connection = {
      endpoint = aws_db_instance.read_replica.endpoint
      port     = aws_db_instance.read_replica.port
      database_name = aws_db_instance.primary.db_name
    }
    parameter_store_config = aws_ssm_parameter.dr_config.name
    failover_status_parameter = aws_ssm_parameter.dr_status.name
  }
  sensitive = false
}

# ============================================================================
# TERRAFORM RANDOM IDENTIFIER
# ============================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}