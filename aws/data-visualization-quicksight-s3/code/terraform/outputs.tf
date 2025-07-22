# =============================================================================
# S3 Bucket Outputs
# =============================================================================

output "raw_data_bucket_name" {
  description = "Name of the S3 bucket for raw data storage"
  value       = aws_s3_bucket.raw_data.id
}

output "raw_data_bucket_arn" {
  description = "ARN of the S3 bucket for raw data storage"
  value       = aws_s3_bucket.raw_data.arn
}

output "processed_data_bucket_name" {
  description = "Name of the S3 bucket for processed data storage"
  value       = aws_s3_bucket.processed_data.id
}

output "processed_data_bucket_arn" {
  description = "ARN of the S3 bucket for processed data storage"
  value       = aws_s3_bucket.processed_data.arn
}

output "athena_results_bucket_name" {
  description = "Name of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.id
}

output "athena_results_bucket_arn" {
  description = "ARN of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.arn
}

# =============================================================================
# Glue Outputs
# =============================================================================

output "glue_database_name" {
  description = "Name of the Glue catalog database"
  value       = aws_glue_catalog_database.main.name
}

output "glue_database_arn" {
  description = "ARN of the Glue catalog database"
  value       = aws_glue_catalog_database.main.arn
}

output "glue_raw_crawler_name" {
  description = "Name of the Glue crawler for raw data"
  value       = aws_glue_crawler.raw_data.name
}

output "glue_processed_crawler_name" {
  description = "Name of the Glue crawler for processed data"
  value       = aws_glue_crawler.processed_data.name
}

output "glue_etl_job_name" {
  description = "Name of the Glue ETL job"
  value       = aws_glue_job.etl_job.name
}

output "glue_etl_job_arn" {
  description = "ARN of the Glue ETL job"
  value       = aws_glue_job.etl_job.arn
}

output "glue_role_arn" {
  description = "ARN of the IAM role used by Glue services"
  value       = aws_iam_role.glue_role.arn
}

# =============================================================================
# Athena Outputs
# =============================================================================

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.main.name
}

output "athena_workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = aws_athena_workgroup.main.arn
}

# =============================================================================
# Lambda Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda automation function"
  value       = aws_lambda_function.automation.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda automation function"
  value       = aws_lambda_function.automation.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

# =============================================================================
# Security Outputs
# =============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.main[0].id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.main[0].arn : null
}

output "kms_alias_name" {
  description = "Alias name of the KMS key (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_alias.main[0].name : null
}

# =============================================================================
# Monitoring Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if email configured)"
  value       = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : null
}

output "cloudwatch_alarm_names" {
  description = "Names of CloudWatch alarms (if enabled)"
  value = var.enable_cloudwatch_alarms ? [
    aws_cloudwatch_metric_alarm.glue_job_failures[0].alarm_name,
    aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name
  ] : []
}

# =============================================================================
# Connection Information
# =============================================================================

output "quicksight_data_source_config" {
  description = "Configuration details for QuickSight data source creation"
  value = {
    athena_workgroup = aws_athena_workgroup.main.name
    database_name    = aws_glue_catalog_database.main.name
    region          = data.aws_region.current.name
  }
}

output "sample_athena_queries" {
  description = "Sample Athena queries to test the data pipeline"
  value = {
    monthly_revenue = "SELECT order_year, order_month, region, total_revenue, total_orders, avg_order_value, unique_customers FROM \"${aws_glue_catalog_database.main.name}\".\"monthly_sales\" ORDER BY order_year, order_month, region;"
    
    top_categories = "SELECT product_category, region, category_revenue, total_quantity, total_orders, ROUND(category_revenue / total_orders, 2) as avg_order_value FROM \"${aws_glue_catalog_database.main.name}\".\"category_performance\" ORDER BY category_revenue DESC;"
    
    customer_analysis = "SELECT customer_tier, region, tier_revenue, tier_orders, tier_customers FROM \"${aws_glue_catalog_database.main.name}\".\"customer_analysis\" ORDER BY tier_revenue DESC;"
  }
}

# =============================================================================
# Deployment Information
# =============================================================================

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Prefix used for naming resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix appended to resource names for uniqueness"
  value       = local.random_suffix
}

# =============================================================================
# Next Steps Information
# =============================================================================

output "next_steps" {
  description = "Next steps to complete the data visualization pipeline setup"
  value = {
    step_1 = "Run the raw data crawler: aws glue start-crawler --name ${aws_glue_crawler.raw_data.name}"
    step_2 = "After crawler completes, run the ETL job: aws glue start-job-run --job-name ${aws_glue_job.etl_job.name}"
    step_3 = "Run the processed data crawler: aws glue start-crawler --name ${aws_glue_crawler.processed_data.name}"
    step_4 = "Create QuickSight data source using Athena workgroup: ${aws_athena_workgroup.main.name}"
    step_5 = "Test queries in Athena console using workgroup: ${aws_athena_workgroup.main.name}"
    step_6 = "Upload additional data files to: s3://${aws_s3_bucket.raw_data.id}/sales-data/"
  }
}

output "quicksight_setup_instructions" {
  description = "Instructions for setting up QuickSight data source"
  value = {
    console_url = "https://quicksight.aws.amazon.com/"
    data_source_type = "Amazon Athena"
    workgroup = aws_athena_workgroup.main.name
    database = aws_glue_catalog_database.main.name
    note = "QuickSight setup requires manual configuration through the AWS Console. Use the provided workgroup and database names."
  }
}

# =============================================================================
# Cost Optimization Information
# =============================================================================

output "cost_optimization_features" {
  description = "Cost optimization features enabled in this deployment"
  value = {
    s3_intelligent_tiering = var.enable_intelligent_tiering
    s3_lifecycle_management = var.s3_lifecycle_enabled
    athena_query_limits = "Enabled with ${var.athena_bytes_scanned_cutoff} bytes scan limit"
    kms_encryption = var.enable_kms_encryption ? "Enabled (additional costs apply)" : "Disabled"
    cloudwatch_monitoring = var.enable_cloudwatch_alarms ? "Enabled" : "Disabled"
  }
}