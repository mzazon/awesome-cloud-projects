# Outputs for S3 Inventory and Storage Analytics Reporting

# ========================================
# S3 Bucket Outputs
# ========================================

output "source_bucket_name" {
  description = "Name of the S3 source bucket being analyzed"
  value       = local.source_bucket_name
}

output "source_bucket_arn" {
  description = "ARN of the S3 source bucket"
  value       = var.source_bucket_name == "" ? aws_s3_bucket.source[0].arn : "arn:aws:s3:::${var.source_bucket_name}"
}

output "destination_bucket_name" {
  description = "Name of the S3 destination bucket for reports"
  value       = aws_s3_bucket.destination.id
}

output "destination_bucket_arn" {
  description = "ARN of the S3 destination bucket"
  value       = aws_s3_bucket.destination.arn
}

output "destination_bucket_domain_name" {
  description = "Domain name of the destination bucket"
  value       = aws_s3_bucket.destination.bucket_domain_name
}

# ========================================
# S3 Configuration Outputs
# ========================================

output "inventory_configuration_id" {
  description = "ID of the S3 inventory configuration"
  value       = aws_s3_bucket_inventory.main.name
}

output "inventory_frequency" {
  description = "Frequency of S3 inventory reports"
  value       = var.inventory_frequency
}

output "analytics_configuration_id" {
  description = "ID of the S3 analytics configuration"
  value       = aws_s3_bucket_analytics_configuration.main.name
}

output "storage_analytics_prefix" {
  description = "Prefix filter for storage class analysis"
  value       = var.storage_analytics_prefix
}

# ========================================
# Athena Outputs
# ========================================

output "athena_database_name" {
  description = "Name of the Athena database for inventory queries"
  value       = aws_glue_catalog_database.inventory.name
}

output "athena_table_name" {
  description = "Name of the Athena table for inventory data"
  value       = var.athena_table_name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for analytics queries"
  value       = aws_athena_workgroup.analytics.name
}

output "athena_results_location" {
  description = "S3 location for Athena query results"
  value       = "s3://${aws_s3_bucket.destination.id}/athena-results/"
}

# ========================================
# Lambda Function Outputs
# ========================================

output "lambda_function_name" {
  description = "Name of the Lambda function for automated reporting"
  value       = var.enable_automated_reporting ? aws_lambda_function.analytics[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = var.enable_automated_reporting ? aws_lambda_function.analytics[0].arn : null
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = var.enable_automated_reporting ? aws_iam_role.lambda_role[0].arn : null
}

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = var.enable_automated_reporting ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

# ========================================
# EventBridge Outputs
# ========================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduling"
  value       = var.enable_automated_reporting ? aws_cloudwatch_event_rule.schedule[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = var.enable_automated_reporting ? aws_cloudwatch_event_rule.schedule[0].arn : null
}

output "reporting_schedule" {
  description = "Schedule expression for automated reporting"
  value       = var.reporting_schedule
}

# ========================================
# CloudWatch Outputs
# ========================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.storage_analytics[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.storage_analytics[0].dashboard_name}" : null
}

# ========================================
# Sample Queries and Commands
# ========================================

output "sample_athena_queries" {
  description = "Sample Athena queries for storage analytics"
  value = {
    storage_class_distribution = "SELECT storage_class, COUNT(*) as object_count, SUM(size) as total_size_bytes FROM ${var.athena_database_name}.${var.athena_table_name} GROUP BY storage_class ORDER BY total_size_bytes DESC;"
    
    old_objects_analysis = "SELECT key, size, storage_class, last_modified_date FROM ${var.athena_database_name}.${var.athena_table_name} WHERE DATE_DIFF('day', DATE_PARSE(last_modified_date, '%Y-%m-%dT%H:%i:%s.%fZ'), CURRENT_DATE) > 30 ORDER BY size DESC LIMIT 100;"
    
    prefix_analysis = "SELECT SUBSTR(key, 1, STRPOS(key, '/')) as prefix, COUNT(*) as object_count, SUM(size) as total_size_bytes FROM ${var.athena_database_name}.${var.athena_table_name} WHERE STRPOS(key, '/') > 0 GROUP BY 1 ORDER BY total_size_bytes DESC;"
    
    cost_optimization = "SELECT storage_class, COUNT(*) as objects, ROUND(SUM(size)/1024/1024/1024, 2) as size_gb, CASE WHEN storage_class='STANDARD' THEN ROUND(SUM(size)*0.023/1024/1024/1024, 2) WHEN storage_class='STANDARD_IA' THEN ROUND(SUM(size)*0.0125/1024/1024/1024, 2) ELSE 0 END as monthly_cost_usd FROM ${var.athena_database_name}.${var.athena_table_name} GROUP BY storage_class;"
  }
}

output "useful_commands" {
  description = "Useful AWS CLI commands for management and monitoring"
  value = {
    list_inventory_configs = "aws s3api list-bucket-inventory-configurations --bucket ${local.source_bucket_name}"
    
    list_analytics_configs = "aws s3api list-bucket-analytics-configurations --bucket ${local.source_bucket_name}"
    
    check_inventory_reports = "aws s3 ls s3://${aws_s3_bucket.destination.id}/inventory-reports/ --recursive"
    
    check_analytics_reports = "aws s3 ls s3://${aws_s3_bucket.destination.id}/analytics-reports/ --recursive"
    
    execute_sample_query = "aws athena start-query-execution --query-string \"SELECT COUNT(*) FROM ${var.athena_database_name}.${var.athena_table_name}\" --result-configuration OutputLocation=s3://${aws_s3_bucket.destination.id}/athena-results/"
    
    invoke_lambda_manually = var.enable_automated_reporting ? "aws lambda invoke --function-name ${aws_lambda_function.analytics[0].function_name} --payload '{}' response.json" : "N/A - Lambda not enabled"
    
    view_lambda_logs = var.enable_automated_reporting ? "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs[0].name}" : "N/A - Lambda not enabled"
  }
}

# ========================================
# Cost and Sizing Information
# ========================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the analytics solution"
  value = {
    s3_inventory = "~$0.0025 per million objects listed"
    athena_queries = "~$5.00 per TB of data scanned"
    lambda_executions = "~$0.20 per million requests (128MB, <1s execution)"
    s3_storage_reports = "~$0.023 per GB/month for Standard storage class"
    cloudwatch_dashboard = "~$3.00 per dashboard per month"
    total_estimate_small_dataset = "~$5-15 per month for datasets under 1TB"
  }
}

output "optimization_recommendations" {
  description = "Recommendations for optimizing costs and performance"
  value = {
    inventory_frequency = "Use Weekly frequency for cost optimization if daily reports aren't required"
    analytics_filters = "Apply specific prefix filters to reduce analysis scope and costs"
    athena_optimization = "Use columnar formats (Parquet) and partitioning for large datasets"
    lifecycle_policies = "Implement automated lifecycle policies based on analytics insights"
    monitoring = "Set up CloudWatch alarms for cost thresholds and unexpected usage"
  }
}

# ========================================
# Next Steps
# ========================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Wait 24-48 hours for first S3 inventory report to be generated",
    "2. Create Athena table schema to query inventory data once reports are available",
    "3. Execute sample queries to validate analytics setup",
    "4. Configure CloudWatch alarms for cost monitoring",
    "5. Review and customize Lambda function queries based on your specific needs",
    "6. Set up QuickSight dashboards for business user access to analytics",
    "7. Implement lifecycle policies based on storage analytics insights"
  ]
}

# ========================================
# Resource Identifiers
# ========================================

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    source_bucket      = local.source_bucket_name
    destination_bucket = aws_s3_bucket.destination.id
    athena_database   = aws_glue_catalog_database.inventory.name
    athena_workgroup  = aws_athena_workgroup.analytics.name
    lambda_function   = var.enable_automated_reporting ? aws_lambda_function.analytics[0].function_name : "Not enabled"
    dashboard_name    = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.storage_analytics[0].dashboard_name : "Not enabled"
    eventbridge_rule  = var.enable_automated_reporting ? aws_cloudwatch_event_rule.schedule[0].name : "Not enabled"
    random_suffix     = local.name_suffix
  }
}