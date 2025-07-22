# S3 Bucket Outputs
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

# Glue Database Outputs
output "glue_database_name" {
  description = "Name of the Glue catalog database"
  value       = aws_glue_catalog_database.analytics_database.name
}

output "glue_database_arn" {
  description = "ARN of the Glue catalog database"
  value       = aws_glue_catalog_database.analytics_database.arn
}

# IAM Role Outputs
output "glue_service_role_name" {
  description = "Name of the IAM role for Glue services"
  value       = aws_iam_role.glue_service_role.name
}

output "glue_service_role_arn" {
  description = "ARN of the IAM role for Glue services"
  value       = aws_iam_role.glue_service_role.arn
}

# Crawler Outputs
output "raw_data_crawler_name" {
  description = "Name of the Glue crawler for raw data discovery"
  value       = aws_glue_crawler.data_discovery.name
}

output "raw_data_crawler_arn" {
  description = "ARN of the Glue crawler for raw data discovery"
  value       = aws_glue_crawler.data_discovery.arn
}

output "processed_data_crawler_name" {
  description = "Name of the Glue crawler for processed data discovery"
  value       = aws_glue_crawler.processed_data_discovery.name
}

output "processed_data_crawler_arn" {
  description = "ARN of the Glue crawler for processed data discovery"
  value       = aws_glue_crawler.processed_data_discovery.arn
}

# ETL Job Outputs
output "etl_job_name" {
  description = "Name of the Glue ETL job"
  value       = aws_glue_job.etl_transformation.name
}

output "etl_job_arn" {
  description = "ARN of the Glue ETL job"
  value       = aws_glue_job.etl_transformation.arn
}

output "etl_script_location" {
  description = "S3 location of the ETL script"
  value       = "s3://${aws_s3_bucket.processed_data.bucket}/${aws_s3_object.etl_script.key}"
}

# Workflow Outputs
output "etl_workflow_name" {
  description = "Name of the Glue workflow"
  value       = aws_glue_workflow.etl_workflow.name
}

output "etl_workflow_arn" {
  description = "ARN of the Glue workflow"
  value       = aws_glue_workflow.etl_workflow.arn
}

# KMS Key Outputs
output "kms_key_id" {
  description = "ID of the KMS key used for S3 encryption"
  value       = aws_kms_key.s3_encryption.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for S3 encryption"
  value       = aws_kms_key.s3_encryption.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for S3 encryption"
  value       = aws_kms_alias.s3_encryption.name
}

# CloudWatch Logs Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Glue jobs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.glue_job_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Glue jobs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.glue_job_logs[0].arn : null
}

# Data Quality Outputs
output "data_quality_ruleset_name" {
  description = "Name of the data quality ruleset"
  value       = var.enable_data_quality ? aws_glue_data_quality_ruleset.sales_data_quality[0].name : null
}

output "data_quality_ruleset_arn" {
  description = "ARN of the data quality ruleset"
  value       = var.enable_data_quality ? aws_glue_data_quality_ruleset.sales_data_quality[0].arn : null
}

# Sample Data Locations
output "sample_sales_data_location" {
  description = "S3 location of sample sales data"
  value       = "s3://${aws_s3_bucket.raw_data.bucket}/${aws_s3_object.sample_sales_csv.key}"
}

output "sample_customers_data_location" {
  description = "S3 location of sample customers data"
  value       = "s3://${aws_s3_bucket.raw_data.bucket}/${aws_s3_object.sample_customers_json.key}"
}

# Trigger Information
output "crawler_trigger_name" {
  description = "Name of the trigger that starts crawlers"
  value       = aws_glue_trigger.start_crawlers.name
}

output "etl_job_trigger_name" {
  description = "Name of the trigger that starts ETL job"
  value       = aws_glue_trigger.start_etl_job.name
}

output "processed_crawler_trigger_name" {
  description = "Name of the trigger that crawls processed data"
  value       = aws_glue_trigger.crawl_processed_data.name
}

# Console URLs for easy access
output "glue_console_database_url" {
  description = "AWS Console URL for the Glue database"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/glue/home?region=${data.aws_region.current.name}#catalog:tab=databases;database=${aws_glue_catalog_database.analytics_database.name}"
}

output "glue_console_jobs_url" {
  description = "AWS Console URL for Glue jobs"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/glue/home?region=${data.aws_region.current.name}#etl:tab=jobs"
}

output "glue_console_crawlers_url" {
  description = "AWS Console URL for Glue crawlers"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/glue/home?region=${data.aws_region.current.name}#catalog:tab=crawlers"
}

output "glue_console_workflows_url" {
  description = "AWS Console URL for Glue workflows"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/glue/home?region=${data.aws_region.current.name}#etl:tab=workflows"
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed ETL pipeline"
  value = <<EOF

## ETL Pipeline Usage Instructions

### 1. Start the ETL Workflow:
```bash
aws glue start-workflow-run --name ${aws_glue_workflow.etl_workflow.name}
```

### 2. Monitor Workflow Progress:
```bash
aws glue get-workflow-run --name ${aws_glue_workflow.etl_workflow.name} --run-id <run-id>
```

### 3. Manual Crawler Execution:
```bash
# Start raw data crawler
aws glue start-crawler --name ${aws_glue_crawler.data_discovery.name}

# Start processed data crawler
aws glue start-crawler --name ${aws_glue_crawler.processed_data_discovery.name}
```

### 4. Manual ETL Job Execution:
```bash
aws glue start-job-run --job-name ${aws_glue_job.etl_transformation.name}
```

### 5. Query Data with Athena:
```bash
# Create Athena workgroup if needed
aws athena create-work-group --name etl-pipeline-workgroup --configuration ResultLocation=s3://${aws_s3_bucket.processed_data.bucket}/athena-results/

# Query enriched data
aws athena start-query-execution \
    --query-string "SELECT customer_id, product_name, total_amount FROM ${aws_glue_catalog_database.analytics_database.name}.enriched_sales LIMIT 10" \
    --result-configuration OutputLocation=s3://${aws_s3_bucket.processed_data.bucket}/athena-results/ \
    --work-group etl-pipeline-workgroup
```

### 6. Upload Additional Data:
```bash
# Upload new sales data
aws s3 cp your-sales-file.csv s3://${aws_s3_bucket.raw_data.bucket}/sales/

# Upload new customer data
aws s3 cp your-customers-file.json s3://${aws_s3_bucket.raw_data.bucket}/customers/
```

### 7. Monitor Logs:
```bash
# View Glue job logs
aws logs describe-log-streams --log-group-name /aws-glue/jobs/logs-v2
```

EOF
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the ETL pipeline (approximate)"
  value = <<EOF

## Estimated Monthly Costs (US East 1, approximate):

### S3 Storage:
- Standard storage (first 50 TB): ~$0.023 per GB/month
- Intelligent Tiering: ~$0.0125 per 1,000 objects monitored

### AWS Glue:
- Crawlers: ~$0.44 per DPU-hour (typically 2 DPUs, runs vary)
- ETL Jobs: ~$0.44 per DPU-hour (${var.number_of_workers} workers)
- Data Catalog: First 1M objects stored and accessed are free

### KMS:
- Key usage: ~$1.00 per month per key
- API requests: ~$0.03 per 10,000 requests

### CloudWatch Logs:
- Ingestion: ~$0.50 per GB ingested
- Storage: ~$0.03 per GB per month

### Total Estimated Monthly Cost:
- Light usage (few GB data, weekly processing): $5-15
- Medium usage (100GB data, daily processing): $20-50
- Heavy usage (1TB+ data, frequent processing): $100+

Note: Costs vary significantly based on data volume, processing frequency, and usage patterns.
EOF
}

# Security Information
output "security_features" {
  description = "Security features implemented in the ETL pipeline"
  value = <<EOF

## Security Features Implemented:

### Encryption:
- S3 buckets encrypted with customer-managed KMS key
- KMS key rotation enabled
- Encrypted data in transit and at rest

### Access Control:
- IAM role with least-privilege permissions
- S3 bucket policies block public access
- Resource-based policies for secure service-to-service communication

### Monitoring:
- CloudWatch logging enabled for all Glue jobs
- S3 access logging available
- CloudTrail integration for API auditing

### Data Protection:
- S3 versioning enabled (optional)
- Lifecycle policies for cost optimization
- Backup and recovery capabilities

### Best Practices:
- No hardcoded credentials
- Service-linked roles for AWS services
- Resource tagging for governance
- Network isolation capabilities

EOF
}