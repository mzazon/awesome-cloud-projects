# Output values for S3 Tables Analytics Infrastructure
# These outputs provide essential information for accessing and managing
# the deployed analytics infrastructure components

# S3 Table Bucket Information
output "table_bucket_name" {
  description = "Name of the S3 table bucket"
  value       = aws_s3tables_table_bucket.analytics.name
}

output "table_bucket_arn" {
  description = "ARN of the S3 table bucket"
  value       = aws_s3tables_table_bucket.analytics.arn
}

output "table_bucket_created_at" {
  description = "Creation timestamp of the S3 table bucket"
  value       = aws_s3tables_table_bucket.analytics.created_at
}

output "table_bucket_owner_account_id" {
  description = "Account ID that owns the S3 table bucket"
  value       = aws_s3tables_table_bucket.analytics.owner_account_id
}

# Namespace Information
output "namespace_name" {
  description = "Name of the table namespace"
  value       = aws_s3tables_namespace.sales_analytics.namespace
}

output "namespace_created_at" {
  description = "Creation timestamp of the namespace"
  value       = aws_s3tables_namespace.sales_analytics.created_at
}

output "namespace_created_by" {
  description = "Account ID that created the namespace"
  value       = aws_s3tables_namespace.sales_analytics.created_by
}

# Table Information
output "table_name" {
  description = "Name of the transaction data table"
  value       = aws_s3tables_table.transaction_data.name
}

output "table_arn" {
  description = "ARN of the transaction data table"
  value       = aws_s3tables_table.transaction_data.arn
}

output "table_metadata_location" {
  description = "S3 location of table metadata"
  value       = aws_s3tables_table.transaction_data.metadata_location
}

output "table_warehouse_location" {
  description = "S3 URI of the table data warehouse location"
  value       = aws_s3tables_table.transaction_data.warehouse_location
}

output "table_version_token" {
  description = "Current version token of the table"
  value       = aws_s3tables_table.transaction_data.version_token
}

output "table_created_at" {
  description = "Creation timestamp of the table"
  value       = aws_s3tables_table.transaction_data.created_at
}

output "table_modified_at" {
  description = "Last modification timestamp of the table"
  value       = aws_s3tables_table.transaction_data.modified_at
}

# AWS Glue Information
output "glue_database_name" {
  description = "Name of the AWS Glue database"
  value       = aws_glue_catalog_database.s3_tables_analytics.name
}

output "glue_database_arn" {
  description = "ARN of the AWS Glue database"
  value       = aws_glue_catalog_database.s3_tables_analytics.arn
}

output "glue_etl_role_arn" {
  description = "ARN of the Glue ETL IAM role"
  value       = aws_iam_role.glue_etl.arn
}

output "glue_etl_role_name" {
  description = "Name of the Glue ETL IAM role"
  value       = aws_iam_role.glue_etl.name
}

# Amazon Athena Information
output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.s3_tables.name
}

output "athena_workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = aws_athena_workgroup.s3_tables.arn
}

output "athena_results_bucket" {
  description = "S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.bucket
}

output "athena_results_bucket_arn" {
  description = "ARN of the Athena results S3 bucket"
  value       = aws_s3_bucket.athena_results.arn
}

output "athena_role_arn" {
  description = "ARN of the Athena IAM role"
  value       = aws_iam_role.athena_s3_tables.arn
}

# Sample Data Information
output "sample_data_bucket" {
  description = "S3 bucket for sample data (if created)"
  value       = var.create_sample_data_bucket ? aws_s3_bucket.sample_data[0].bucket : null
}

output "sample_data_bucket_arn" {
  description = "ARN of the sample data S3 bucket (if created)"
  value       = var.create_sample_data_bucket ? aws_s3_bucket.sample_data[0].arn : null
}

output "sample_data_file_key" {
  description = "S3 key for the sample transactions file (if created)"
  value       = var.create_sample_data_bucket ? aws_s3_object.sample_transactions[0].key : null
}

# Encryption Information
output "kms_key_arn" {
  description = "ARN of the KMS key for S3 Tables encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.s3_tables[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key for S3 Tables encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.s3_tables[0].key_id : null
}

output "kms_alias_name" {
  description = "Alias name of the KMS key (if enabled)"
  value       = var.enable_encryption ? aws_kms_alias.s3_tables[0].name : null
}

# Monitoring Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.s3_tables_analytics.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.s3_tables_analytics.arn
}

# Quick Start Commands
output "athena_query_example" {
  description = "Example Athena query to test the table"
  value = "SELECT COUNT(*) as total_transactions, region, AVG(price) as avg_price FROM \"${aws_glue_catalog_database.s3_tables_analytics.name}\".\"${aws_s3tables_table.transaction_data.name}\" GROUP BY region;"
}

output "sample_aws_cli_commands" {
  description = "Sample AWS CLI commands for interacting with S3 Tables"
  value = {
    list_tables = "aws s3tables list-tables --table-bucket-arn ${aws_s3tables_table_bucket.analytics.arn} --namespace ${aws_s3tables_namespace.sales_analytics.namespace}"
    get_table   = "aws s3tables get-table --table-bucket-arn ${aws_s3tables_table_bucket.analytics.arn} --namespace ${aws_s3tables_namespace.sales_analytics.namespace} --name ${aws_s3tables_table.transaction_data.name}"
    athena_query = "aws athena start-query-execution --query-string \"SELECT * FROM \\\"${aws_glue_catalog_database.s3_tables_analytics.name}\\\".\\\"${aws_s3tables_table.transaction_data.name}\\\" LIMIT 10;\" --work-group ${aws_athena_workgroup.s3_tables.name}"
  }
}

# Resource Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    table_bucket    = aws_s3tables_table_bucket.analytics.name
    namespace       = aws_s3tables_namespace.sales_analytics.namespace
    table           = aws_s3tables_table.transaction_data.name
    glue_database   = aws_glue_catalog_database.s3_tables_analytics.name
    athena_workgroup = aws_athena_workgroup.s3_tables.name
    encryption_enabled = var.enable_encryption
    maintenance_enabled = var.maintenance_enabled
    region = data.aws_region.current.name
    account_id = data.aws_caller_identity.current.account_id
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload sample data to S3 bucket: ${var.create_sample_data_bucket ? aws_s3_bucket.sample_data[0].bucket : "Create sample data bucket first"}",
    "2. Configure AWS Glue ETL job to load data into S3 Tables",
    "3. Query data using Athena workgroup: ${aws_athena_workgroup.s3_tables.name}",
    "4. Set up QuickSight data source for visualization",
    "5. Monitor table performance and maintenance in CloudWatch logs"
  ]
}