# Terraform Outputs for QLDB Infrastructure

# QLDB Ledger Information
output "qldb_ledger_name" {
  description = "Name of the created QLDB ledger"
  value       = aws_qldb_ledger.financial_ledger.name
}

output "qldb_ledger_arn" {
  description = "ARN of the created QLDB ledger"
  value       = aws_qldb_ledger.financial_ledger.arn
}

output "qldb_ledger_id" {
  description = "Unique identifier of the QLDB ledger"
  value       = aws_qldb_ledger.financial_ledger.id
}

output "qldb_deletion_protection" {
  description = "Deletion protection status of the QLDB ledger"
  value       = aws_qldb_ledger.financial_ledger.deletion_protection
}

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for QLDB exports"
  value       = aws_s3_bucket.qldb_exports.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for QLDB exports"
  value       = aws_s3_bucket.qldb_exports.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.qldb_exports.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.qldb_exports.bucket_regional_domain_name
}

# Kinesis Stream Information
output "kinesis_stream_name" {
  description = "Name of the Kinesis stream for journal streaming"
  value       = aws_kinesis_stream.qldb_journal_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis stream"
  value       = aws_kinesis_stream.qldb_journal_stream.arn
}

output "kinesis_shard_count" {
  description = "Number of shards in the Kinesis stream"
  value       = aws_kinesis_stream.qldb_journal_stream.shard_count
}

output "kinesis_retention_period" {
  description = "Retention period of the Kinesis stream in hours"
  value       = aws_kinesis_stream.qldb_journal_stream.retention_period
}

# IAM Role Information
output "iam_role_name" {
  description = "Name of the IAM role for QLDB streaming"
  value       = aws_iam_role.qldb_stream_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for QLDB streaming"
  value       = aws_iam_role.qldb_stream_role.arn
}

# QLDB Stream Information
output "qldb_stream_id" {
  description = "ID of the QLDB journal stream"
  value       = aws_qldb_stream.journal_to_kinesis.id
}

output "qldb_stream_arn" {
  description = "ARN of the QLDB journal stream"
  value       = aws_qldb_stream.journal_to_kinesis.arn
}

output "qldb_stream_name" {
  description = "Name of the QLDB journal stream"
  value       = aws_qldb_stream.journal_to_kinesis.stream_name
}

# CloudWatch Log Group Information (conditional)
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.qldb_monitoring[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group (if enabled)"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.qldb_monitoring[0].arn : null
}

# CloudWatch Alarms Information (conditional)
output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring"
  value = var.enable_cloudwatch_logs ? {
    read_io_alarm    = aws_cloudwatch_metric_alarm.qldb_read_io_high[0].alarm_name
    write_io_alarm   = aws_cloudwatch_metric_alarm.qldb_write_io_high[0].alarm_name
    kinesis_alarm    = aws_cloudwatch_metric_alarm.kinesis_incoming_records[0].alarm_name
  } : {}
}

# Configuration Information
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    aws_region              = var.aws_region
    environment             = var.environment
    deletion_protection     = var.enable_deletion_protection
    kinesis_aggregation     = var.enable_kinesis_aggregation
    s3_encryption          = var.s3_encryption_type
    s3_versioning          = var.enable_s3_versioning
    cloudwatch_logs        = var.enable_cloudwatch_logs
    random_suffix          = local.random_suffix
  }
}

# Resource URLs and Connection Information
output "resource_endpoints" {
  description = "Connection endpoints and URLs for accessing resources"
  value = {
    qldb_console_url = "https://console.aws.amazon.com/qldb/home?region=${var.aws_region}#ledger-details/${aws_qldb_ledger.financial_ledger.name}"
    s3_console_url   = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.qldb_exports.bucket}?region=${var.aws_region}"
    kinesis_console_url = "https://console.aws.amazon.com/kinesis/home?region=${var.aws_region}#/streams/details/${aws_kinesis_stream.qldb_journal_stream.name}"
  }
}

# CLI Commands for Common Operations
output "cli_commands" {
  description = "Useful AWS CLI commands for interacting with the infrastructure"
  value = {
    get_ledger_digest = "aws qldb get-digest --name ${aws_qldb_ledger.financial_ledger.name}"
    list_tables = "aws qldb describe-ledger --name ${aws_qldb_ledger.financial_ledger.name}"
    check_stream_status = "aws qldb describe-journal-kinesis-stream --ledger-name ${aws_qldb_ledger.financial_ledger.name} --stream-id ${aws_qldb_stream.journal_to_kinesis.id}"
    export_to_s3 = "aws qldb export-journal-to-s3 --name ${aws_qldb_ledger.financial_ledger.name} --role-arn ${aws_iam_role.qldb_stream_role.arn} --s3-export-configuration Bucket=${aws_s3_bucket.qldb_exports.bucket},Prefix=${var.s3_export_prefix},EncryptionConfiguration='{\"ObjectEncryptionType\":\"${var.s3_encryption_type}\"}' --inclusive-start-time $(date -u -d '1 hour ago' +%%Y-%%m-%%dT%%H:%%M:%%SZ) --exclusive-end-time $(date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ)"
  }
}

# Cost Estimation Information
output "cost_considerations" {
  description = "Important cost considerations for the deployed resources"
  value = {
    qldb_pricing_model = "Pay per I/O request and storage used"
    kinesis_pricing = "Pay per shard hour and data ingestion"
    s3_pricing = "Pay per storage used and requests"
    estimated_monthly_cost = "Varies based on usage - typically $10-100 for development workloads"
    cost_optimization_tips = [
      "Use lifecycle policies to move old S3 data to cheaper storage classes",
      "Monitor QLDB I/O requests to optimize query patterns",
      "Consider reducing Kinesis shard count for low-volume environments",
      "Enable S3 Intelligent Tiering for automatic cost optimization"
    ]
  }
}

# Security and Compliance Information
output "security_features" {
  description = "Security and compliance features implemented"
  value = {
    qldb_features = [
      "Immutable append-only journal",
      "Cryptographic verification with SHA-256",
      "ACID compliance with serializable isolation",
      "IAM-based access control"
    ]
    s3_security = [
      "Server-side encryption enabled",
      "Public access blocked",
      "Versioning enabled (if configured)",
      "Lifecycle management"
    ]
    kinesis_security = [
      "KMS encryption at rest",
      "IAM-controlled access",
      "VPC endpoint support available"
    ]
    compliance_standards = [
      "SOX (Sarbanes-Oxley)",
      "PCI DSS",
      "Basel III",
      "GDPR (with proper data handling)"
    ]
  }
}

# PartiQL Scripts Location
output "partiql_scripts" {
  description = "Location of PartiQL scripts for database setup and queries"
  value = {
    create_tables_script = "${path.module}/scripts/create-tables.sql"
    sample_data_script = "${path.module}/scripts/sample-data.sql"
    audit_queries_script = "${path.module}/scripts/audit-queries.sql"
  }
}