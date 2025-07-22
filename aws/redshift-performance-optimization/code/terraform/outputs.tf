# Redshift cluster information
output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift cluster"
  value       = aws_redshift_cluster.performance_cluster.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "Endpoint of the Redshift cluster"
  value       = aws_redshift_cluster.performance_cluster.endpoint
  sensitive   = true
}

output "redshift_cluster_port" {
  description = "Port of the Redshift cluster"
  value       = aws_redshift_cluster.performance_cluster.port
}

output "redshift_database_name" {
  description = "Name of the default database"
  value       = aws_redshift_cluster.performance_cluster.database_name
}

output "redshift_master_username" {
  description = "Master username for the Redshift cluster"
  value       = aws_redshift_cluster.performance_cluster.master_username
}

# Connection information
output "redshift_connection_string" {
  description = "PostgreSQL connection string for the Redshift cluster"
  value       = "postgresql://${aws_redshift_cluster.performance_cluster.master_username}:PASSWORD@${aws_redshift_cluster.performance_cluster.endpoint}:${aws_redshift_cluster.performance_cluster.port}/${aws_redshift_cluster.performance_cluster.database_name}"
  sensitive   = true
}

output "redshift_jdbc_url" {
  description = "JDBC URL for the Redshift cluster"
  value       = "jdbc:redshift://${aws_redshift_cluster.performance_cluster.endpoint}:${aws_redshift_cluster.performance_cluster.port}/${aws_redshift_cluster.performance_cluster.database_name}"
}

# Security and access information
output "redshift_iam_role_arn" {
  description = "ARN of the IAM role attached to the Redshift cluster"
  value       = aws_iam_role.redshift_role.arn
}

output "redshift_security_group_id" {
  description = "Security group ID for the Redshift cluster"
  value       = aws_security_group.redshift_sg.id
}

output "redshift_subnet_group_name" {
  description = "Name of the Redshift subnet group"
  value       = aws_redshift_subnet_group.redshift_subnet_group.name
}

# Credentials and secrets
output "redshift_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Redshift credentials"
  value       = aws_secretsmanager_secret.redshift_credentials.arn
}

output "redshift_credentials_secret_name" {
  description = "Name of the Secrets Manager secret containing Redshift credentials"
  value       = aws_secretsmanager_secret.redshift_credentials.name
}

# Performance optimization resources
output "redshift_parameter_group_name" {
  description = "Name of the optimized parameter group"
  value       = aws_redshift_parameter_group.optimized_wlm.name
}

output "redshift_wlm_configuration" {
  description = "Workload Management configuration applied to the cluster"
  value       = "Automatic WLM with concurrency scaling enabled"
}

# Monitoring and alerting
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for Redshift performance monitoring"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.redshift_performance.dashboard_name}"
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for performance metrics"
  value       = aws_cloudwatch_log_group.performance_metrics.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for performance alerts"
  value       = aws_sns_topic.performance_alerts.arn
}

output "cpu_alarm_name" {
  description = "Name of the CPU utilization CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.redshift_high_cpu.alarm_name
}

output "queue_alarm_name" {
  description = "Name of the queue length CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.redshift_high_queue_length.alarm_name
}

# Maintenance automation
output "lambda_function_name" {
  description = "Name of the Lambda function for automated maintenance"
  value       = aws_lambda_function.redshift_maintenance.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for automated maintenance"
  value       = aws_lambda_function.redshift_maintenance.arn
}

output "maintenance_schedule" {
  description = "Cron expression for the maintenance schedule"
  value       = aws_cloudwatch_event_rule.maintenance_schedule.schedule_expression
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for maintenance scheduling"
  value       = aws_cloudwatch_event_rule.maintenance_schedule.name
}

# Storage and logging
output "audit_logs_bucket_name" {
  description = "Name of the S3 bucket for audit logs (if logging is enabled)"
  value       = var.enable_logging ? aws_s3_bucket.redshift_logs[0].bucket : null
}

output "audit_logs_bucket_arn" {
  description = "ARN of the S3 bucket for audit logs (if logging is enabled)"
  value       = var.enable_logging ? aws_s3_bucket.redshift_logs[0].arn : null
}

# Network information
output "vpc_id" {
  description = "ID of the VPC containing the Redshift cluster"
  value       = aws_vpc.redshift_vpc.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets containing the Redshift cluster"
  value       = aws_subnet.redshift_private_subnets[*].id
}

# Performance insights and recommendations
output "performance_optimization_summary" {
  description = "Summary of performance optimizations applied"
  value = {
    wlm_configuration        = "Automatic WLM with concurrency scaling"
    enhanced_vpc_routing     = "Enabled"
    parameter_group         = aws_redshift_parameter_group.optimized_wlm.name
    automated_maintenance   = "Lambda function with nightly schedule"
    monitoring_dashboard    = aws_cloudwatch_dashboard.redshift_performance.dashboard_name
    cpu_threshold          = "${var.cpu_alarm_threshold}%"
    queue_threshold        = var.queue_length_threshold
  }
}

# Quick start commands
output "psql_connection_command" {
  description = "psql command to connect to the Redshift cluster (replace PASSWORD)"
  value       = "psql -h ${aws_redshift_cluster.performance_cluster.endpoint} -U ${aws_redshift_cluster.performance_cluster.master_username} -d ${aws_redshift_cluster.performance_cluster.database_name} -p ${aws_redshift_cluster.performance_cluster.port}"
  sensitive   = true
}

output "aws_cli_describe_cluster_command" {
  description = "AWS CLI command to describe the Redshift cluster"
  value       = "aws redshift describe-clusters --cluster-identifier ${aws_redshift_cluster.performance_cluster.cluster_identifier} --region ${var.aws_region}"
}

output "retrieve_password_command" {
  description = "AWS CLI command to retrieve the master password from Secrets Manager"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.redshift_credentials.name} --region ${var.aws_region} --query SecretString --output text | jq -r .password"
  sensitive   = true
}