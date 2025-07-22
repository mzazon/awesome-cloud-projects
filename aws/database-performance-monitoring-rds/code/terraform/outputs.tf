# Database Information
output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.id
}

output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_instance_resource_id" {
  description = "RDS instance resource ID (used for Performance Insights)"
  value       = aws_db_instance.main.resource_id
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "db_instance_availability_zone" {
  description = "RDS instance availability zone"
  value       = aws_db_instance.main.availability_zone
}

# Performance Insights Information
output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled"
  value       = aws_db_instance.main.performance_insights_enabled
}

output "performance_insights_retention_period" {
  description = "Performance Insights retention period"
  value       = aws_db_instance.main.performance_insights_retention_period
}

output "performance_insights_kms_key_id" {
  description = "Performance Insights KMS key ID"
  value       = aws_db_instance.main.performance_insights_kms_key_id
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.performance_analyzer.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.performance_analyzer.arn
}

output "lambda_function_invoke_arn" {
  description = "Lambda function invoke ARN"
  value       = aws_lambda_function.performance_analyzer.invoke_arn
}

# S3 Bucket Information
output "s3_bucket_name" {
  description = "S3 bucket name for performance reports"
  value       = aws_s3_bucket.performance_reports.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.performance_reports.arn
}

output "s3_bucket_domain_name" {
  description = "S3 bucket domain name"
  value       = aws_s3_bucket.performance_reports.bucket_domain_name
}

# SNS Topic Information
output "sns_topic_arn" {
  description = "SNS topic ARN for performance alerts"
  value       = aws_sns_topic.performance_alerts.arn
}

output "sns_topic_name" {
  description = "SNS topic name"
  value       = aws_sns_topic.performance_alerts.name
}

# EventBridge Rule Information
output "eventbridge_rule_name" {
  description = "EventBridge rule name"
  value       = aws_cloudwatch_event_rule.performance_analysis_trigger.name
}

output "eventbridge_rule_arn" {
  description = "EventBridge rule ARN"
  value       = aws_cloudwatch_event_rule.performance_analysis_trigger.arn
}

# CloudWatch Alarm Information
output "cloudwatch_alarm_names" {
  description = "List of CloudWatch alarm names"
  value = [
    aws_cloudwatch_metric_alarm.high_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.high_connections.alarm_name,
    aws_cloudwatch_metric_alarm.high_load_events.alarm_name,
    aws_cloudwatch_metric_alarm.problematic_queries.alarm_name
  ]
}

output "cloudwatch_alarm_arns" {
  description = "List of CloudWatch alarm ARNs"
  value = [
    aws_cloudwatch_metric_alarm.high_cpu.arn,
    aws_cloudwatch_metric_alarm.high_connections.arn,
    aws_cloudwatch_metric_alarm.high_load_events.arn,
    aws_cloudwatch_metric_alarm.problematic_queries.arn
  ]
}

# Dashboard Information
output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.performance_dashboard.dashboard_name
}

output "cloudwatch_dashboard_arn" {
  description = "CloudWatch dashboard ARN"
  value       = aws_cloudwatch_dashboard.performance_dashboard.dashboard_arn
}

# IAM Role Information
output "lambda_role_arn" {
  description = "Lambda execution role ARN"
  value       = aws_iam_role.lambda_role.arn
}

output "rds_monitoring_role_arn" {
  description = "RDS enhanced monitoring role ARN"
  value       = aws_iam_role.rds_monitoring_role.arn
}

# Security Group Information
output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds_sg.id
}

output "rds_security_group_arn" {
  description = "RDS security group ARN"
  value       = aws_security_group.rds_sg.arn
}

# Subnet Group Information
output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.main.name
}

output "db_subnet_group_arn" {
  description = "DB subnet group ARN"
  value       = aws_db_subnet_group.main.arn
}

# Connection Information
output "database_connection_string" {
  description = "Database connection string (without password)"
  value       = "mysql://${var.db_username}:PASSWORD@${aws_db_instance.main.endpoint}:${aws_db_instance.main.port}/testdb"
  sensitive   = true
}

# Console URLs
output "performance_insights_console_url" {
  description = "AWS Console URL for Performance Insights"
  value       = "https://${var.aws_region}.console.aws.amazon.com/rds/home?region=${var.aws_region}#performance-insights-v20206:/resourceId/${aws_db_instance.main.resource_id}"
}

output "cloudwatch_dashboard_console_url" {
  description = "AWS Console URL for CloudWatch Dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.performance_dashboard.dashboard_name}"
}

output "rds_console_url" {
  description = "AWS Console URL for RDS instance"
  value       = "https://${var.aws_region}.console.aws.amazon.com/rds/home?region=${var.aws_region}#database:id=${aws_db_instance.main.id};is-cluster=false"
}

output "lambda_console_url" {
  description = "AWS Console URL for Lambda function"
  value       = "https://${var.aws_region}.console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${aws_lambda_function.performance_analyzer.function_name}"
}

output "s3_console_url" {
  description = "AWS Console URL for S3 bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.performance_reports.bucket}"
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    rds_instance_id           = aws_db_instance.main.id
    lambda_function_name      = aws_lambda_function.performance_analyzer.function_name
    s3_bucket_name           = aws_s3_bucket.performance_reports.bucket
    sns_topic_name           = aws_sns_topic.performance_alerts.name
    dashboard_name           = aws_cloudwatch_dashboard.performance_dashboard.dashboard_name
    performance_insights_enabled = aws_db_instance.main.performance_insights_enabled
    monitoring_interval      = aws_db_instance.main.monitoring_interval
    total_alarms_created     = 4
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps for using the deployed infrastructure"
  value = [
    "1. Confirm SNS email subscription if notification_email was provided",
    "2. Generate database load using the provided SQL script",
    "3. Monitor Performance Insights dashboard for database metrics",
    "4. Review CloudWatch dashboard for comprehensive monitoring",
    "5. Check S3 bucket for automated analysis reports",
    "6. Verify Lambda function execution logs in CloudWatch",
    "7. Test alarm notifications by triggering performance thresholds"
  ]
}