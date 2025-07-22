# Outputs for Aurora Serverless v2 Cost Optimization Infrastructure
# This file defines all outputs that will be displayed after successful deployment

# Aurora Cluster Outputs
output "aurora_cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.aurora_serverless_v2.cluster_identifier
}

output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = aws_rds_cluster.aurora_serverless_v2.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = aws_rds_cluster.aurora_serverless_v2.reader_endpoint
}

output "aurora_cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.aurora_serverless_v2.port
}

output "aurora_cluster_database_name" {
  description = "Aurora cluster database name"
  value       = aws_rds_cluster.aurora_serverless_v2.database_name
}

output "aurora_cluster_master_username" {
  description = "Aurora cluster master username"
  value       = aws_rds_cluster.aurora_serverless_v2.master_username
  sensitive   = true
}

output "aurora_cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.aurora_serverless_v2.arn
}

output "aurora_cluster_resource_id" {
  description = "Aurora cluster resource ID"
  value       = aws_rds_cluster.aurora_serverless_v2.cluster_resource_id
}

# Aurora Instance Outputs
output "aurora_writer_instance_id" {
  description = "Aurora writer instance identifier"
  value       = aws_rds_cluster_instance.writer.identifier
}

output "aurora_writer_instance_endpoint" {
  description = "Aurora writer instance endpoint"
  value       = aws_rds_cluster_instance.writer.endpoint
}

output "aurora_reader_instance_ids" {
  description = "List of Aurora reader instance identifiers"
  value       = var.enable_read_replicas ? aws_rds_cluster_instance.readers[*].identifier : []
}

output "aurora_reader_instance_endpoints" {
  description = "List of Aurora reader instance endpoints"
  value       = var.enable_read_replicas ? aws_rds_cluster_instance.readers[*].endpoint : []
}

# Serverless Configuration Outputs
output "serverless_v2_min_capacity" {
  description = "Aurora Serverless v2 minimum capacity (ACU)"
  value       = aws_rds_cluster.aurora_serverless_v2.serverlessv2_scaling_configuration[0].min_capacity
}

output "serverless_v2_max_capacity" {
  description = "Aurora Serverless v2 maximum capacity (ACU)"
  value       = aws_rds_cluster.aurora_serverless_v2.serverlessv2_scaling_configuration[0].max_capacity
}

# Security Group Outputs
output "aurora_security_group_id" {
  description = "Aurora security group ID"
  value       = aws_security_group.aurora.id
}

output "aurora_security_group_arn" {
  description = "Aurora security group ARN"
  value       = aws_security_group.aurora.arn
}

# Parameter Group Outputs
output "aurora_cluster_parameter_group_name" {
  description = "Aurora cluster parameter group name"
  value       = aws_rds_cluster_parameter_group.aurora_cost_optimized.name
}

output "aurora_cluster_parameter_group_arn" {
  description = "Aurora cluster parameter group ARN"
  value       = aws_rds_cluster_parameter_group.aurora_cost_optimized.arn
}

# Subnet Group Outputs
output "aurora_subnet_group_name" {
  description = "Aurora subnet group name"
  value       = local.use_existing_vpc ? null : aws_db_subnet_group.aurora[0].name
}

output "aurora_subnet_group_arn" {
  description = "Aurora subnet group ARN"
  value       = local.use_existing_vpc ? null : aws_db_subnet_group.aurora[0].arn
}

# Lambda Function Outputs
output "cost_aware_scaler_function_name" {
  description = "Cost-aware scaling Lambda function name"
  value       = aws_lambda_function.cost_aware_scaler.function_name
}

output "cost_aware_scaler_function_arn" {
  description = "Cost-aware scaling Lambda function ARN"
  value       = aws_lambda_function.cost_aware_scaler.arn
}

output "auto_pause_resume_function_name" {
  description = "Auto-pause/resume Lambda function name"
  value       = aws_lambda_function.auto_pause_resume.function_name
}

output "auto_pause_resume_function_arn" {
  description = "Auto-pause/resume Lambda function ARN"
  value       = aws_lambda_function.auto_pause_resume.arn
}

# IAM Role Outputs
output "lambda_execution_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Lambda execution role name"
  value       = aws_iam_role.lambda_execution.name
}

# EventBridge Outputs
output "cost_aware_scaling_rule_arn" {
  description = "Cost-aware scaling EventBridge rule ARN"
  value       = aws_cloudwatch_event_rule.cost_aware_scaling.arn
}

output "auto_pause_resume_rule_arn" {
  description = "Auto-pause/resume EventBridge rule ARN"
  value       = aws_cloudwatch_event_rule.auto_pause_resume.arn
}

# Monitoring Outputs
output "cloudwatch_alarms" {
  description = "CloudWatch alarm names for cost monitoring"
  value = var.enable_cost_monitoring ? {
    high_acu_usage           = aws_cloudwatch_metric_alarm.high_acu_usage[0].alarm_name
    sustained_high_capacity  = aws_cloudwatch_metric_alarm.sustained_high_capacity[0].alarm_name
  } : {}
}

output "sns_topic_arn" {
  description = "SNS topic ARN for cost alerts"
  value       = var.enable_cost_monitoring ? aws_sns_topic.cost_alerts[0].arn : null
}

# Budget Outputs
output "budget_name" {
  description = "AWS Budget name for Aurora costs"
  value       = var.enable_cost_monitoring ? aws_budgets_budget.aurora_monthly[0].name : null
}

# Connection Information
output "connection_info" {
  description = "Database connection information"
  value = {
    endpoint     = aws_rds_cluster.aurora_serverless_v2.endpoint
    port         = aws_rds_cluster.aurora_serverless_v2.port
    database     = aws_rds_cluster.aurora_serverless_v2.database_name
    username     = aws_rds_cluster.aurora_serverless_v2.master_username
    cluster_id   = aws_rds_cluster.aurora_serverless_v2.cluster_identifier
  }
  sensitive = true
}

# Cost Optimization Configuration
output "cost_optimization_config" {
  description = "Cost optimization configuration summary"
  value = {
    min_capacity              = var.serverless_min_capacity
    max_capacity              = var.serverless_max_capacity
    environment               = var.environment
    scaling_schedule          = var.cost_aware_scaling_schedule
    pause_resume_schedule     = var.auto_pause_resume_schedule
    performance_insights      = var.enable_performance_insights
    cost_monitoring_enabled   = var.enable_cost_monitoring
    monthly_budget_limit      = var.monthly_budget_limit
  }
}

# VPC and Network Outputs
output "vpc_id" {
  description = "VPC ID used for Aurora cluster"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used for Aurora cluster"
  value       = local.subnet_ids
}

# Performance Monitoring
output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled"
  value       = var.enable_performance_insights
}

output "cloudwatch_logs_exports" {
  description = "CloudWatch log exports enabled"
  value       = aws_rds_cluster.aurora_serverless_v2.enabled_cloudwatch_logs_exports
}

# Recovery and Backup Information
output "backup_configuration" {
  description = "Backup configuration details"
  value = {
    retention_period    = var.backup_retention_period
    backup_window      = var.preferred_backup_window
    maintenance_window = var.preferred_maintenance_window
    storage_encrypted  = aws_rds_cluster.aurora_serverless_v2.storage_encrypted
    kms_key_id        = aws_rds_cluster.aurora_serverless_v2.kms_key_id
  }
}