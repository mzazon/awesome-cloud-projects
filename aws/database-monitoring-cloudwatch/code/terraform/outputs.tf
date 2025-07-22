# =============================================================================
# Outputs for Database Monitoring Dashboards with CloudWatch
# =============================================================================

# =============================================================================
# RDS DATABASE OUTPUTS
# =============================================================================

output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.monitoring_demo.id
}

output "db_instance_identifier" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.monitoring_demo.identifier
}

output "db_instance_arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.monitoring_demo.arn
}

output "db_instance_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.monitoring_demo.endpoint
}

output "db_instance_address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.monitoring_demo.address
}

output "db_instance_port" {
  description = "The database port"
  value       = aws_db_instance.monitoring_demo.port
}

output "db_instance_name" {
  description = "The database name"
  value       = aws_db_instance.monitoring_demo.db_name
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = aws_db_instance.monitoring_demo.username
  sensitive   = true
}

output "db_instance_engine" {
  description = "The database engine"
  value       = aws_db_instance.monitoring_demo.engine
}

output "db_instance_engine_version" {
  description = "The running version of the database"
  value       = aws_db_instance.monitoring_demo.engine_version_actual
}

output "db_instance_class" {
  description = "The RDS instance class"
  value       = aws_db_instance.monitoring_demo.instance_class
}

output "db_instance_status" {
  description = "The RDS instance status"
  value       = aws_db_instance.monitoring_demo.status
}

output "db_instance_availability_zone" {
  description = "The availability zone of the instance"
  value       = aws_db_instance.monitoring_demo.availability_zone
}

output "db_instance_multi_az" {
  description = "If the RDS instance is multi AZ enabled"
  value       = aws_db_instance.monitoring_demo.multi_az
}

output "db_instance_backup_retention_period" {
  description = "The backup retention period"
  value       = aws_db_instance.monitoring_demo.backup_retention_period
}

output "db_instance_backup_window" {
  description = "The backup window"
  value       = aws_db_instance.monitoring_demo.backup_window
}

output "db_instance_maintenance_window" {
  description = "The instance maintenance window"
  value       = aws_db_instance.monitoring_demo.maintenance_window
}

output "db_instance_storage_encrypted" {
  description = "Whether the DB instance is encrypted"
  value       = aws_db_instance.monitoring_demo.storage_encrypted
}

output "db_instance_performance_insights_enabled" {
  description = "Whether Performance Insights is enabled"
  value       = aws_db_instance.monitoring_demo.performance_insights_enabled
}

output "db_instance_monitoring_interval" {
  description = "The monitoring interval"
  value       = aws_db_instance.monitoring_demo.monitoring_interval
}

# =============================================================================
# SNS TOPIC OUTPUTS
# =============================================================================

output "sns_topic_arn" {
  description = "The ARN of the SNS topic for database alerts"
  value       = aws_sns_topic.database_alerts.arn
}

output "sns_topic_name" {
  description = "The name of the SNS topic for database alerts"
  value       = aws_sns_topic.database_alerts.name
}

output "sns_topic_owner" {
  description = "The AWS Account ID of the SNS topic owner"
  value       = aws_sns_topic.database_alerts.owner
}

output "sns_subscription_arn" {
  description = "The ARN of the SNS email subscription (if email provided)"
  value       = var.alert_email != "" ? aws_sns_topic_subscription.email_alerts[0].arn : null
}

# =============================================================================
# CLOUDWATCH DASHBOARD OUTPUTS
# =============================================================================

output "cloudwatch_dashboard_arn" {
  description = "The ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.database_monitoring.dashboard_arn
}

output "cloudwatch_dashboard_name" {
  description = "The name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.database_monitoring.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "The URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.database_monitoring.dashboard_name}"
}

# =============================================================================
# CLOUDWATCH ALARMS OUTPUTS
# =============================================================================

output "cloudwatch_alarms" {
  description = "Map of CloudWatch alarm names and their ARNs"
  value = {
    high_cpu           = aws_cloudwatch_metric_alarm.high_cpu.arn
    high_connections   = aws_cloudwatch_metric_alarm.high_connections.arn
    low_storage        = aws_cloudwatch_metric_alarm.low_storage.arn
    low_memory         = aws_cloudwatch_metric_alarm.low_memory.arn
    high_db_load       = aws_cloudwatch_metric_alarm.high_db_load.arn
    high_read_latency  = aws_cloudwatch_metric_alarm.high_read_latency.arn
    high_write_latency = aws_cloudwatch_metric_alarm.high_write_latency.arn
  }
}

output "high_cpu_alarm_name" {
  description = "The name of the high CPU alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
}

output "high_connections_alarm_name" {
  description = "The name of the high connections alarm"
  value       = aws_cloudwatch_metric_alarm.high_connections.alarm_name
}

output "low_storage_alarm_name" {
  description = "The name of the low storage alarm"
  value       = aws_cloudwatch_metric_alarm.low_storage.alarm_name
}

output "low_memory_alarm_name" {
  description = "The name of the low memory alarm"
  value       = aws_cloudwatch_metric_alarm.low_memory.alarm_name
}

output "high_db_load_alarm_name" {
  description = "The name of the high database load alarm"
  value       = aws_cloudwatch_metric_alarm.high_db_load.alarm_name
}

output "high_read_latency_alarm_name" {
  description = "The name of the high read latency alarm"
  value       = aws_cloudwatch_metric_alarm.high_read_latency.alarm_name
}

output "high_write_latency_alarm_name" {
  description = "The name of the high write latency alarm"
  value       = aws_cloudwatch_metric_alarm.high_write_latency.alarm_name
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "rds_monitoring_role_arn" {
  description = "The ARN of the IAM role for RDS enhanced monitoring"
  value       = aws_iam_role.rds_monitoring_role.arn
}

output "rds_monitoring_role_name" {
  description = "The name of the IAM role for RDS enhanced monitoring"
  value       = aws_iam_role.rds_monitoring_role.name
}

# =============================================================================
# CONNECTION INFORMATION
# =============================================================================

output "database_connection_command" {
  description = "Example command to connect to the database"
  value       = "mysql -h ${aws_db_instance.monitoring_demo.address} -P ${aws_db_instance.monitoring_demo.port} -u ${aws_db_instance.monitoring_demo.username} -p ${aws_db_instance.monitoring_demo.db_name}"
  sensitive   = true
}

output "database_connection_string" {
  description = "Database connection string"
  value       = "mysql://${aws_db_instance.monitoring_demo.username}:PASSWORD@${aws_db_instance.monitoring_demo.address}:${aws_db_instance.monitoring_demo.port}/${aws_db_instance.monitoring_demo.db_name}"
  sensitive   = true
}

# =============================================================================
# MONITORING INFORMATION
# =============================================================================

output "monitoring_setup_complete" {
  description = "Confirmation that monitoring setup is complete"
  value       = "Database monitoring setup complete. Dashboard: ${aws_cloudwatch_dashboard.database_monitoring.dashboard_name}, Alarms: ${length(keys(module.outputs.cloudwatch_alarms))}, SNS Topic: ${aws_sns_topic.database_alerts.name}"
}

output "performance_insights_url" {
  description = "URL to Performance Insights (if enabled)"
  value = var.db_performance_insights_enabled ? (
    "https://${data.aws_region.current.name}.console.aws.amazon.com/rds/home?region=${data.aws_region.current.name}#performance-insights-v20206:/resourceId/${aws_db_instance.monitoring_demo.resource_id}"
  ) : "Performance Insights not enabled"
}

output "cloudwatch_logs_groups" {
  description = "CloudWatch Log Groups for RDS logs (if enabled)"
  value = length(var.db_enabled_cloudwatch_logs_exports) > 0 ? [
    for log_type in var.db_enabled_cloudwatch_logs_exports :
    "/aws/rds/instance/${aws_db_instance.monitoring_demo.identifier}/${log_type}"
  ] : []
}

# =============================================================================
# COST INFORMATION
# =============================================================================

output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs"
  value = {
    rds_instance    = "RDS ${var.db_instance_class} instance: ~$13-20/month (varies by region)"
    storage         = "Storage (${var.db_allocated_storage}GB ${var.db_storage_type}): ~$2-4/month"
    monitoring      = "Enhanced monitoring (${var.db_monitoring_interval}s): ~$1-3/month"
    performance_insights = var.db_performance_insights_enabled ? "Performance Insights: Free for 7 days retention" : "Performance Insights: Disabled"
    cloudwatch      = "CloudWatch alarms (${length(keys(module.outputs.cloudwatch_alarms))} alarms): ~$0.70/month"
    sns             = "SNS notifications: ~$0.50/month for typical usage"
    total_estimate  = "Total estimated monthly cost: ~$17-30/month"
  }
}

# =============================================================================
# NEXT STEPS
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Visit the CloudWatch dashboard: ${aws_cloudwatch_dashboard.database_monitoring.dashboard_name}",
    "2. ${var.alert_email != "" ? "Check your email (${var.alert_email}) to confirm SNS subscription" : "Configure SNS subscription by adding an email to alert_email variable"}",
    "3. Test database connectivity using the provided connection command",
    "4. Generate some database activity to see metrics in the dashboard",
    "5. Review and adjust alarm thresholds based on your workload patterns",
    "6. Consider enabling additional CloudWatch log exports if needed",
    "7. Set up backup verification procedures",
    "8. Review Performance Insights data for query optimization opportunities"
  ]
}