# Outputs for AWS Glue Data Lake Ingestion Pipeline
# These outputs provide essential information about created resources

# =====================================================
# Data Lake Storage Outputs
# =====================================================

output "s3_bucket_name" {
  description = "Name of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.bucket_regional_domain_name
}

# =====================================================
# AWS Glue Data Catalog Outputs
# =====================================================

output "glue_database_name" {
  description = "Name of the AWS Glue database"
  value       = aws_glue_catalog_database.data_lake.name
}

output "glue_database_arn" {
  description = "ARN of the AWS Glue database"
  value       = aws_glue_catalog_database.data_lake.arn
}

output "glue_database_catalog_id" {
  description = "Catalog ID of the AWS Glue database"
  value       = aws_glue_catalog_database.data_lake.catalog_id
}

# =====================================================
# AWS Glue Crawler Outputs
# =====================================================

output "glue_crawler_name" {
  description = "Name of the AWS Glue crawler"
  value       = aws_glue_crawler.data_lake_crawler.name
}

output "glue_crawler_arn" {
  description = "ARN of the AWS Glue crawler"
  value       = aws_glue_crawler.data_lake_crawler.arn
}

# =====================================================
# AWS Glue ETL Job Outputs
# =====================================================

output "glue_job_name" {
  description = "Name of the AWS Glue ETL job"
  value       = aws_glue_job.data_lake_etl.name
}

output "glue_job_arn" {
  description = "ARN of the AWS Glue ETL job"
  value       = aws_glue_job.data_lake_etl.arn
}

output "glue_job_script_location" {
  description = "S3 location of the Glue ETL script"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/scripts/etl-script.py"
}

# =====================================================
# AWS Glue Workflow Outputs
# =====================================================

output "glue_workflow_name" {
  description = "Name of the AWS Glue workflow"
  value       = aws_glue_workflow.data_lake_pipeline.name
}

output "glue_workflow_arn" {
  description = "ARN of the AWS Glue workflow"
  value       = aws_glue_workflow.data_lake_pipeline.arn
}

# =====================================================
# IAM Role Outputs
# =====================================================

output "glue_role_name" {
  description = "Name of the AWS Glue IAM role"
  value       = aws_iam_role.glue_role.name
}

output "glue_role_arn" {
  description = "ARN of the AWS Glue IAM role"
  value       = aws_iam_role.glue_role.arn
}

# =====================================================
# Data Quality Outputs (Conditional)
# =====================================================

output "data_quality_ruleset_name" {
  description = "Name of the data quality ruleset (if enabled)"
  value       = var.enable_data_quality_rules ? aws_glue_data_quality_ruleset.data_lake_quality[0].name : null
}

# =====================================================
# Monitoring Outputs (Conditional)
# =====================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts (if enabled)"
  value       = var.enable_cloudwatch_monitoring && var.notification_email != "" ? aws_sns_topic.pipeline_alerts[0].arn : null
}

output "cloudwatch_alarm_job_failure" {
  description = "Name of the CloudWatch alarm for job failures (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.glue_job_failure[0].alarm_name : null
}

output "cloudwatch_alarm_crawler_failure" {
  description = "Name of the CloudWatch alarm for crawler failures (if enabled)"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.crawler_failure[0].alarm_name : null
}

# =====================================================
# Amazon Athena Outputs
# =====================================================

output "athena_workgroup_name" {
  description = "Name of the Amazon Athena workgroup"
  value       = aws_athena_workgroup.data_lake.name
}

output "athena_workgroup_arn" {
  description = "ARN of the Amazon Athena workgroup"
  value       = aws_athena_workgroup.data_lake.arn
}

output "athena_results_location" {
  description = "S3 location for Athena query results"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/athena-results/"
}

# =====================================================
# Connection Information for External Tools
# =====================================================

output "athena_connection_info" {
  description = "Connection information for Amazon Athena"
  value = {
    workgroup        = aws_athena_workgroup.data_lake.name
    database         = aws_glue_catalog_database.data_lake.name
    s3_results_path  = "s3://${aws_s3_bucket.data_lake.bucket}/athena-results/"
    region          = data.aws_region.current.name
  }
}

output "data_lake_structure" {
  description = "Data lake folder structure and locations"
  value = {
    raw_data_path     = "s3://${aws_s3_bucket.data_lake.bucket}/raw-data/"
    bronze_layer_path = "s3://${aws_s3_bucket.data_lake.bucket}/processed-data/bronze/"
    silver_layer_path = "s3://${aws_s3_bucket.data_lake.bucket}/processed-data/silver/"
    gold_layer_path   = "s3://${aws_s3_bucket.data_lake.bucket}/processed-data/gold/"
    scripts_path      = "s3://${aws_s3_bucket.data_lake.bucket}/scripts/"
    temp_path         = "s3://${aws_s3_bucket.data_lake.bucket}/temp/"
  }
}

# =====================================================
# Sample Query Examples
# =====================================================

output "sample_athena_queries" {
  description = "Sample Athena queries to get started"
  value = {
    list_tables = "SHOW TABLES IN ${aws_glue_catalog_database.data_lake.name};"
    query_events = "SELECT * FROM ${aws_glue_catalog_database.data_lake.name}.raw_events LIMIT 10;"
    query_customers = "SELECT * FROM ${aws_glue_catalog_database.data_lake.name}.raw_customers LIMIT 10;"
    daily_sales = "SELECT event_date, category, total_purchases, total_revenue FROM ${aws_glue_catalog_database.data_lake.name}.gold_daily_sales ORDER BY event_date DESC;"
  }
}

# =====================================================
# Getting Started Information
# =====================================================

output "getting_started" {
  description = "Getting started information for the data lake pipeline"
  value = {
    step_1 = "Run the crawler manually: aws glue start-crawler --name ${aws_glue_crawler.data_lake_crawler.name}"
    step_2 = "Monitor crawler progress: aws glue get-crawler --name ${aws_glue_crawler.data_lake_crawler.name}"
    step_3 = "Run ETL job: aws glue start-job-run --job-name ${aws_glue_job.data_lake_etl.name}"
    step_4 = "Query data with Athena using workgroup: ${aws_athena_workgroup.data_lake.name}"
    step_5 = "Access AWS Glue Console to monitor workflow: https://console.aws.amazon.com/glue/home?region=${data.aws_region.current.name}#etl:tab=workflows"
  }
}

# =====================================================
# Cost Estimation Information
# =====================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the data lake pipeline"
  value = {
    note = "Costs depend on data volume and processing frequency"
    s3_storage = "S3 storage costs: ~$0.023 per GB/month (Standard)"
    glue_crawler = "Glue crawler: ~$0.44 per DPU-hour"
    glue_etl = "Glue ETL job: ~$0.44 per DPU-hour"
    athena_queries = "Athena queries: ~$5.00 per TB of data scanned"
    cloudwatch = "CloudWatch: ~$0.30 per custom metric per month"
  }
}