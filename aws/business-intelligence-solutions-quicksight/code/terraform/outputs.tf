# Core infrastructure outputs
output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# S3 outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket storing QuickSight data"
  value       = aws_s3_bucket.quicksight_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing QuickSight data"
  value       = aws_s3_bucket.quicksight_data.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.quicksight_data.region
}

output "s3_data_path" {
  description = "S3 path to the sample sales data CSV file"
  value       = "s3://${aws_s3_bucket.quicksight_data.bucket}/sales/sales_data.csv"
}

output "s3_historical_data_path" {
  description = "S3 path to the historical sales data CSV file"
  value       = "s3://${aws_s3_bucket.quicksight_data.bucket}/sales/historical/sales_data_historical.csv"
}

# IAM role outputs
output "quicksight_s3_role_arn" {
  description = "ARN of the IAM role for QuickSight S3 access"
  value       = aws_iam_role.quicksight_s3_role.arn
}

output "quicksight_s3_role_name" {
  description = "Name of the IAM role for QuickSight S3 access"
  value       = aws_iam_role.quicksight_s3_role.name
}

output "quicksight_service_role_arn" {
  description = "ARN of the IAM role for QuickSight service operations"
  value       = aws_iam_role.quicksight_service_role.arn
}

output "quicksight_service_role_name" {
  description = "Name of the IAM role for QuickSight service operations"
  value       = aws_iam_role.quicksight_service_role.name
}

# RDS outputs (conditional)
output "rds_endpoint" {
  description = "RDS instance endpoint (if created)"
  value       = var.create_rds_instance ? aws_db_instance.quicksight_demo[0].endpoint : null
}

output "rds_database_name" {
  description = "RDS database name (if created)"
  value       = var.create_rds_instance ? aws_db_instance.quicksight_demo[0].db_name : null
}

output "rds_username" {
  description = "RDS master username (if created)"
  value       = var.create_rds_instance ? aws_db_instance.quicksight_demo[0].username : null
  sensitive   = true
}

output "rds_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing RDS credentials (if created)"
  value       = var.create_rds_instance ? aws_secretsmanager_secret.rds_password[0].arn : null
}

output "rds_security_group_id" {
  description = "Security group ID for RDS instance (if created)"
  value       = var.create_rds_instance ? aws_security_group.rds_quicksight[0].id : null
}

# QuickSight configuration outputs
output "quicksight_edition" {
  description = "QuickSight edition configured"
  value       = var.quicksight_edition
}

output "quicksight_authentication_method" {
  description = "QuickSight authentication method"
  value       = var.quicksight_authentication_method
}

output "quicksight_session_timeout" {
  description = "QuickSight session timeout in minutes"
  value       = var.quicksight_session_timeout
}

# QuickSight resource identifiers
output "quicksight_data_source_id" {
  description = "QuickSight data source identifier"
  value       = "sales-data-s3"
}

output "quicksight_dataset_id" {
  description = "QuickSight dataset identifier"
  value       = "sales-dataset"
}

output "quicksight_analysis_id" {
  description = "QuickSight analysis identifier"
  value       = "sales-analysis"
}

output "quicksight_dashboard_id" {
  description = "QuickSight dashboard identifier"
  value       = "sales-dashboard"
}

# QuickSight resource ARNs
output "quicksight_data_source_arn" {
  description = "QuickSight data source ARN"
  value       = "arn:aws:quicksight:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:datasource/sales-data-s3"
}

output "quicksight_dataset_arn" {
  description = "QuickSight dataset ARN"
  value       = "arn:aws:quicksight:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dataset/sales-dataset"
}

output "quicksight_analysis_arn" {
  description = "QuickSight analysis ARN"
  value       = "arn:aws:quicksight:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:analysis/sales-analysis"
}

output "quicksight_dashboard_arn" {
  description = "QuickSight dashboard ARN"
  value       = "arn:aws:quicksight:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dashboard/sales-dashboard"
}

# Monitoring outputs
output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for QuickSight monitoring (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.quicksight_monitoring[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN for QuickSight monitoring (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.quicksight_monitoring[0].arn : null
}

output "sns_topic_arn" {
  description = "SNS topic ARN for QuickSight alerts (if enabled)"
  value       = var.enable_cost_monitoring && var.notification_email != "" ? aws_sns_topic.quicksight_alerts[0].arn : null
}

output "budget_name" {
  description = "AWS Budget name for cost monitoring (if enabled)"
  value       = var.enable_cost_monitoring ? aws_budgets_budget.quicksight_monthly[0].name : null
}

# Configuration file output
output "quicksight_setup_config_file" {
  description = "Path to the generated QuickSight setup configuration file"
  value       = "${path.module}/quicksight_setup_config.json"
}

# Data refresh configuration outputs
output "refresh_schedule_frequency" {
  description = "Configured data refresh frequency"
  value       = var.refresh_schedule_frequency
}

output "refresh_time_of_day" {
  description = "Configured refresh time of day"
  value       = var.refresh_time_of_day
}

# Feature flag outputs
output "features_enabled" {
  description = "Map of enabled features"
  value = {
    spice_enabled              = var.enable_quicksight_spice
    scheduled_refresh_enabled  = var.enable_scheduled_refresh
    dashboard_sharing_enabled  = var.enable_dashboard_sharing
    embedded_analytics_enabled = var.enable_embedded_analytics
    row_level_security_enabled = var.enable_row_level_security
    cloudwatch_monitoring_enabled = var.enable_cloudwatch_monitoring
    cost_monitoring_enabled    = var.enable_cost_monitoring
    s3_versioning_enabled     = var.enable_s3_versioning
    s3_lifecycle_enabled      = var.s3_lifecycle_enabled
    rds_instance_created      = var.create_rds_instance
  }
}

# Security configuration outputs
output "allowed_embed_domains" {
  description = "List of domains allowed for embedded analytics"
  value       = var.allowed_embed_domains
}

# Cost monitoring outputs
output "cost_alert_threshold" {
  description = "Monthly cost alert threshold in USD"
  value       = var.cost_alert_threshold
}

output "notification_email" {
  description = "Email address for notifications (masked for security)"
  value       = var.notification_email != "" ? "${substr(var.notification_email, 0, 3)}***@${split("@", var.notification_email)[1]}" : "Not configured"
}

# Resource tags output
output "common_tags" {
  description = "Common tags applied to all resources"
  value = merge(var.additional_tags, {
    Project     = "QuickSight-BI-Solutions"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "business-intelligence-solutions-quicksight"
  })
}

# CLI commands for QuickSight setup (informational)
output "next_steps" {
  description = "Next steps for completing QuickSight setup"
  value = {
    step_1 = "Enable QuickSight in AWS Console: https://quicksight.aws.amazon.com/"
    step_2 = "Use the generated configuration file: ${path.module}/quicksight_setup_config.json"
    step_3 = "Run the deployment scripts in the scripts/ directory"
    step_4 = "Create QuickSight data sources, datasets, and dashboards using AWS CLI or Console"
    step_5 = "Configure dashboard sharing and embedded analytics as needed"
  }
}

# Summary output
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    s3_bucket           = aws_s3_bucket.quicksight_data.bucket
    iam_roles_created   = 2
    rds_instance        = var.create_rds_instance ? "Created" : "Not created"
    monitoring_enabled  = var.enable_cloudwatch_monitoring
    cost_alerts_enabled = var.enable_cost_monitoring
    region             = data.aws_region.current.name
    account_id         = data.aws_caller_identity.current.account_id
  }
}