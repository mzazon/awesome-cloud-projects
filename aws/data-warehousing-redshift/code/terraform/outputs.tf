# Outputs for Amazon Redshift Data Warehouse Infrastructure

# Redshift Serverless Outputs
output "redshift_namespace_name" {
  description = "Name of the Redshift Serverless namespace"
  value       = aws_redshiftserverless_namespace.main.namespace_name
}

output "redshift_namespace_id" {
  description = "ID of the Redshift Serverless namespace"
  value       = aws_redshiftserverless_namespace.main.namespace_id
}

output "redshift_workgroup_name" {
  description = "Name of the Redshift Serverless workgroup"
  value       = aws_redshiftserverless_workgroup.main.workgroup_name
}

output "redshift_workgroup_id" {
  description = "ID of the Redshift Serverless workgroup"
  value       = aws_redshiftserverless_workgroup.main.workgroup_id
}

output "redshift_workgroup_arn" {
  description = "ARN of the Redshift Serverless workgroup"
  value       = aws_redshiftserverless_workgroup.main.arn
}

output "redshift_endpoint" {
  description = "Endpoint for connecting to the Redshift workgroup"
  value       = aws_redshiftserverless_workgroup.main.endpoint[0].address
  sensitive   = false
}

output "redshift_port" {
  description = "Port number for connecting to the Redshift workgroup"
  value       = aws_redshiftserverless_workgroup.main.endpoint[0].port
}

output "database_name" {
  description = "Name of the default database"
  value       = aws_redshiftserverless_namespace.main.db_name
}

output "admin_username" {
  description = "Admin username for the Redshift database"
  value       = aws_redshiftserverless_namespace.main.admin_username
  sensitive   = true
}

# S3 Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.bucket_domain_name
}

output "sample_data_s3_paths" {
  description = "S3 paths to the uploaded sample data files"
  value = var.create_sample_data ? {
    sales_data    = "s3://${aws_s3_bucket.data_bucket.bucket}/data/sales_data.csv"
    customer_data = "s3://${aws_s3_bucket.data_bucket.bucket}/data/customer_data.csv"
  } : {}
}

# IAM Outputs
output "redshift_iam_role_arn" {
  description = "ARN of the IAM role used by Redshift"
  value       = aws_iam_role.redshift_role.arn
}

output "redshift_iam_role_name" {
  description = "Name of the IAM role used by Redshift"
  value       = aws_iam_role.redshift_role.name
}

# Security Outputs
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.redshift_key[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.redshift_key[0].arn : null
}

# Usage Limit Outputs
output "usage_limit_id" {
  description = "ID of the Redshift usage limit"
  value       = var.enable_usage_limits ? aws_redshiftserverless_usage_limit.main[0].usage_limit_id : null
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Redshift logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.redshift_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Redshift logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.redshift_logs[0].arn : null
}

# Connection Information
output "connection_info" {
  description = "Information needed to connect to the Redshift data warehouse"
  value = {
    endpoint  = aws_redshiftserverless_workgroup.main.endpoint[0].address
    port      = aws_redshiftserverless_workgroup.main.endpoint[0].port
    database  = aws_redshiftserverless_namespace.main.db_name
    username  = aws_redshiftserverless_namespace.main.admin_username
  }
  sensitive = true
}

# SQL Commands for Data Loading
output "sql_commands" {
  description = "SQL commands to create tables and load data"
  value = var.create_sample_data ? {
    create_tables = local.create_tables_sql
    load_data     = local.load_data_sql
    sample_queries = local.sample_queries_sql
  } : {}
}

# Next Steps
output "next_steps" {
  description = "Instructions for next steps after deployment"
  value = [
    "1. Connect to Redshift using Query Editor v2 in the AWS Console",
    "2. Use the connection information from the 'connection_info' output",
    "3. Execute the SQL commands from the 'sql_commands' output to create tables and load data",
    "4. Run the sample analytical queries to test the data warehouse functionality",
    "5. Configure your BI tools to connect to the Redshift endpoint"
  ]
}