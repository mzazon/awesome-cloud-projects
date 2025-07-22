# S3 bucket outputs
output "analytics_bucket_name" {
  description = "Name of the S3 bucket for analytics data"
  value       = aws_s3_bucket.analytics_bucket.bucket
}

output "analytics_bucket_arn" {
  description = "ARN of the S3 bucket for analytics data"
  value       = aws_s3_bucket.analytics_bucket.arn
}

output "analytics_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.analytics_bucket.bucket_domain_name
}

output "athena_results_bucket_name" {
  description = "Name of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.bucket
}

output "athena_results_bucket_arn" {
  description = "ARN of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.arn
}

# S3 Intelligent-Tiering configuration outputs
output "intelligent_tiering_configuration_id" {
  description = "ID of the S3 Intelligent-Tiering configuration"
  value       = aws_s3_bucket_intelligent_tiering_configuration.analytics_intelligent_tiering.name
}

output "intelligent_tiering_prefix" {
  description = "S3 prefix covered by Intelligent-Tiering"
  value       = var.intelligent_tiering_prefix
}

output "archive_access_days" {
  description = "Days after which objects transition to Archive Access tier"
  value       = var.archive_access_days
}

output "deep_archive_access_days" {
  description = "Days after which objects transition to Deep Archive Access tier"
  value       = var.deep_archive_access_days
}

# AWS Glue outputs
output "glue_database_name" {
  description = "Name of the AWS Glue database"
  value       = aws_glue_catalog_database.analytics_database.name
}

output "glue_database_arn" {
  description = "ARN of the AWS Glue database"
  value       = aws_glue_catalog_database.analytics_database.arn
}

output "glue_table_name" {
  description = "Name of the AWS Glue table"
  value       = aws_glue_catalog_table.transaction_logs.name
}

output "glue_table_arn" {
  description = "ARN of the AWS Glue table"
  value       = aws_glue_catalog_table.transaction_logs.arn
}

# Athena outputs
output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.analytics_workgroup.name
}

output "athena_workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = aws_athena_workgroup.analytics_workgroup.arn
}

output "athena_query_limit_bytes" {
  description = "Maximum bytes Athena can scan per query"
  value       = var.athena_query_limit_bytes
}

# CloudWatch Dashboard outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.s3_cost_optimization[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.s3_cost_optimization[0].dashboard_name}" : null
}

# Cost Anomaly Detection outputs
output "cost_anomaly_detector_arn" {
  description = "ARN of the cost anomaly detector"
  value       = var.enable_cost_anomaly_detection ? aws_ce_anomaly_detector.s3_cost_anomaly[0].arn : null
}

output "cost_anomaly_subscription_arn" {
  description = "ARN of the cost anomaly subscription"
  value       = var.enable_cost_anomaly_detection ? aws_ce_anomaly_subscription.s3_cost_anomaly_subscription[0].arn : null
}

# Useful commands and information
output "sample_athena_queries" {
  description = "Sample Athena queries to test the setup"
  value = [
    "SELECT COUNT(*) as total_transactions FROM ${aws_glue_catalog_database.analytics_database.name}.${aws_glue_catalog_table.transaction_logs.name};",
    "SELECT user_id, COUNT(*) as transaction_count FROM ${aws_glue_catalog_database.analytics_database.name}.${aws_glue_catalog_table.transaction_logs.name} GROUP BY user_id ORDER BY transaction_count DESC LIMIT 10;",
    "SELECT DATE(timestamp) as date, COUNT(*) as daily_transactions FROM ${aws_glue_catalog_database.analytics_database.name}.${aws_glue_catalog_table.transaction_logs.name} GROUP BY DATE(timestamp) ORDER BY date;"
  ]
}

output "s3_upload_command" {
  description = "AWS CLI command to upload data with Intelligent-Tiering"
  value       = "aws s3 cp your-data-file s3://${aws_s3_bucket.analytics_bucket.bucket}/${var.intelligent_tiering_prefix} --storage-class INTELLIGENT_TIERING"
}

output "cost_analysis_cli_commands" {
  description = "AWS CLI commands for cost analysis"
  value = [
    "# Check S3 storage metrics:",
    "aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name BucketSizeBytes --dimensions Name=BucketName,Value=${aws_s3_bucket.analytics_bucket.bucket} Name=StorageType,Value=IntelligentTieringFAStorage --start-time $(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 3600 --statistics Average",
    "",
    "# Check Athena query metrics:",
    "aws cloudwatch get-metric-statistics --namespace AWS/Athena --metric-name DataScannedInBytes --dimensions Name=WorkGroup,Value=${aws_athena_workgroup.analytics_workgroup.name} --start-time $(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 3600 --statistics Sum"
  ]
}

# Resource identifiers for external integration
output "resource_identifiers" {
  description = "Resource identifiers for external systems integration"
  value = {
    bucket_name           = aws_s3_bucket.analytics_bucket.bucket
    glue_database_name    = aws_glue_catalog_database.analytics_database.name
    glue_table_name       = aws_glue_catalog_table.transaction_logs.name
    athena_workgroup_name = aws_athena_workgroup.analytics_workgroup.name
    aws_region           = data.aws_region.current.name
    aws_account_id       = data.aws_caller_identity.current.account_id
  }
}

# Configuration summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    intelligent_tiering_enabled = true
    archive_access_days        = var.archive_access_days
    deep_archive_access_days   = var.deep_archive_access_days
    versioning_enabled         = var.enable_versioning
    encryption_enabled         = true
    cost_monitoring_enabled    = var.enable_cloudwatch_dashboard
    anomaly_detection_enabled  = var.enable_cost_anomaly_detection
    athena_query_limit_gb      = var.athena_query_limit_bytes / 1024 / 1024 / 1024
  }
}