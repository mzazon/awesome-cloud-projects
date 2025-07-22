# DMS Replication Instance Outputs
output "replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "replication_instance_id" {
  description = "ID of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_id
}

output "replication_instance_endpoint" {
  description = "Endpoint of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_private_ips
}

output "replication_instance_public_ips" {
  description = "Public IP addresses of the DMS replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_public_ips
}

# DMS Endpoints Outputs
output "source_endpoint_arn" {
  description = "ARN of the DMS source endpoint"
  value       = aws_dms_endpoint.source.endpoint_arn
}

output "source_endpoint_id" {
  description = "ID of the DMS source endpoint"
  value       = aws_dms_endpoint.source.endpoint_id
}

output "target_endpoint_arn" {
  description = "ARN of the DMS target endpoint"
  value       = aws_dms_endpoint.target.endpoint_arn
}

output "target_endpoint_id" {
  description = "ID of the DMS target endpoint"
  value       = aws_dms_endpoint.target.endpoint_id
}

# DMS Migration Task Outputs
output "migration_task_arn" {
  description = "ARN of the DMS migration task"
  value       = aws_dms_replication_task.main.replication_task_arn
}

output "migration_task_id" {
  description = "ID of the DMS migration task"
  value       = aws_dms_replication_task.main.replication_task_id
}

output "migration_task_status" {
  description = "Status of the DMS migration task"
  value       = aws_dms_replication_task.main.status
}

# DMS Subnet Group Outputs
output "subnet_group_id" {
  description = "ID of the DMS subnet group"
  value       = aws_dms_replication_subnet_group.main.replication_subnet_group_id
}

output "subnet_group_arn" {
  description = "ARN of the DMS subnet group"
  value       = aws_dms_replication_subnet_group.main.replication_subnet_group_arn
}

# SNS Topic Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for DMS notifications"
  value       = var.notification_email != "" ? aws_sns_topic.dms_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for DMS notifications"
  value       = var.notification_email != "" ? aws_sns_topic.dms_notifications[0].name : null
}

# CloudWatch Log Group Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for DMS"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.dms[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for DMS"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.dms[0].arn : null
}

# KMS Key Outputs
output "kms_key_id" {
  description = "ID of the KMS key used for DMS encryption"
  value       = var.enable_kms_encryption && var.kms_key_id == "" ? aws_kms_key.dms[0].key_id : var.kms_key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for DMS encryption"
  value       = var.enable_kms_encryption && var.kms_key_id == "" ? aws_kms_key.dms[0].arn : null
}

output "kms_alias_name" {
  description = "Alias name of the KMS key used for DMS encryption"
  value       = var.enable_kms_encryption && var.kms_key_id == "" ? aws_kms_alias.dms[0].name : null
}

# CloudWatch Alarms Outputs
output "task_failure_alarm_arn" {
  description = "ARN of the CloudWatch alarm for DMS task failures"
  value       = aws_cloudwatch_metric_alarm.dms_task_failure.arn
}

output "high_latency_alarm_arn" {
  description = "ARN of the CloudWatch alarm for DMS high latency"
  value       = aws_cloudwatch_metric_alarm.dms_high_latency.arn
}

output "low_memory_alarm_arn" {
  description = "ARN of the CloudWatch alarm for DMS low memory"
  value       = aws_cloudwatch_metric_alarm.dms_low_memory.arn
}

# Event Subscription Outputs
output "event_subscription_arn" {
  description = "ARN of the DMS event subscription"
  value       = var.notification_email != "" ? aws_dms_event_subscription.main[0].arn : null
}

output "event_subscription_name" {
  description = "Name of the DMS event subscription"
  value       = var.notification_email != "" ? aws_dms_event_subscription.main[0].name : null
}

# Network Configuration Outputs
output "vpc_id" {
  description = "VPC ID where DMS resources are deployed"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used by DMS"
  value       = local.subnet_ids
}

# Migration Configuration Outputs
output "migration_type" {
  description = "Type of migration configured"
  value       = var.migration_type
}

output "data_validation_enabled" {
  description = "Whether data validation is enabled"
  value       = var.enable_data_validation
}

output "table_mappings" {
  description = "Table mappings configuration for the migration task"
  value       = local.table_mappings
  sensitive   = false
}

# Resource Names for Reference
output "resource_names" {
  description = "Map of all resource names created by this module"
  value = {
    replication_instance = aws_dms_replication_instance.main.replication_instance_id
    source_endpoint      = aws_dms_endpoint.source.endpoint_id
    target_endpoint      = aws_dms_endpoint.target.endpoint_id
    migration_task       = aws_dms_replication_task.main.replication_task_id
    subnet_group         = aws_dms_replication_subnet_group.main.replication_subnet_group_id
    log_group           = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.dms[0].name : null
    sns_topic           = var.notification_email != "" ? aws_sns_topic.dms_notifications[0].name : null
    kms_key             = var.enable_kms_encryption && var.kms_key_id == "" ? aws_kms_key.dms[0].key_id : null
  }
}

# Connection Test Commands
output "connection_test_commands" {
  description = "AWS CLI commands to test database connections"
  value = {
    test_source_connection = "aws dms test-connection --replication-instance-arn ${aws_dms_replication_instance.main.replication_instance_arn} --endpoint-arn ${aws_dms_endpoint.source.endpoint_arn}"
    test_target_connection = "aws dms test-connection --replication-instance-arn ${aws_dms_replication_instance.main.replication_instance_arn} --endpoint-arn ${aws_dms_endpoint.target.endpoint_arn}"
  }
}

# Monitoring Commands
output "monitoring_commands" {
  description = "AWS CLI commands for monitoring migration progress"
  value = {
    task_status = "aws dms describe-replication-tasks --filters 'Name=replication-task-id,Values=${aws_dms_replication_task.main.replication_task_id}' --query 'ReplicationTasks[0].{Status:Status,Progress:ReplicationTaskStats}'"
    table_statistics = "aws dms describe-table-statistics --replication-task-arn ${aws_dms_replication_task.main.replication_task_arn}"
    connection_status = "aws dms describe-connections --filters 'Name=replication-instance-arn,Values=${aws_dms_replication_instance.main.replication_instance_arn}'"
  }
}

# Task Management Commands
output "task_management_commands" {
  description = "AWS CLI commands for managing the migration task"
  value = {
    start_task = "aws dms start-replication-task --replication-task-arn ${aws_dms_replication_task.main.replication_task_arn} --start-replication-task-type start-replication"
    stop_task  = "aws dms stop-replication-task --replication-task-arn ${aws_dms_replication_task.main.replication_task_arn}"
    reload_task = "aws dms start-replication-task --replication-task-arn ${aws_dms_replication_task.main.replication_task_arn} --start-replication-task-type reload-target"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    replication_instance = "Estimated $${formatdate(\"MM\", timestamp())} USD/month for ${var.replication_instance_class} instance"
    storage              = "Estimated $${var.allocated_storage * 0.115} USD/month for ${var.allocated_storage}GB storage"
    data_transfer        = "Data transfer costs vary based on migration volume and network routes"
    cloudwatch_logs      = "CloudWatch logs cost varies based on log volume and retention"
    note                 = "Actual costs may vary based on usage patterns, region, and AWS pricing changes"
  }
}