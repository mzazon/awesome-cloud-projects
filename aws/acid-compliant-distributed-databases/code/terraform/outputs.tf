# ============================================================================
# QLDB Ledger Outputs
# ============================================================================

output "qldb_ledger_name" {
  description = "Name of the QLDB ledger"
  value       = aws_qldb_ledger.financial_ledger.name
}

output "qldb_ledger_arn" {
  description = "ARN of the QLDB ledger"
  value       = aws_qldb_ledger.financial_ledger.arn
}

output "qldb_ledger_id" {
  description = "ID of the QLDB ledger"
  value       = aws_qldb_ledger.financial_ledger.id
}

output "qldb_deletion_protection" {
  description = "Whether deletion protection is enabled for the QLDB ledger"
  value       = aws_qldb_ledger.financial_ledger.deletion_protection
}

# ============================================================================
# QLDB Journal Streaming Outputs
# ============================================================================

output "qldb_stream_id" {
  description = "ID of the QLDB journal stream"
  value       = aws_qldb_stream.journal_stream.stream_id
}

output "qldb_stream_arn" {
  description = "ARN of the QLDB journal stream"
  value       = aws_qldb_stream.journal_stream.arn
}

output "qldb_stream_name" {
  description = "Name of the QLDB journal stream"
  value       = aws_qldb_stream.journal_stream.stream_name
}

output "qldb_stream_status" {
  description = "Status of the QLDB journal stream"
  value       = aws_qldb_stream.journal_stream.id
}

# ============================================================================
# S3 Bucket Outputs
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for journal exports"
  value       = aws_s3_bucket.journal_exports.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for journal exports"
  value       = aws_s3_bucket.journal_exports.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.journal_exports.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.journal_exports.bucket_regional_domain_name
}

output "s3_bucket_region" {
  description = "AWS region of the S3 bucket"
  value       = aws_s3_bucket.journal_exports.region
}

# ============================================================================
# Kinesis Stream Outputs
# ============================================================================

output "kinesis_stream_name" {
  description = "Name of the Kinesis stream for journal data"
  value       = aws_kinesis_stream.journal_stream.name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis stream for journal data"
  value       = aws_kinesis_stream.journal_stream.arn
}

output "kinesis_stream_shard_count" {
  description = "Number of shards in the Kinesis stream"
  value       = aws_kinesis_stream.journal_stream.shard_count
}

output "kinesis_stream_retention_period" {
  description = "Retention period of the Kinesis stream in hours"
  value       = aws_kinesis_stream.journal_stream.retention_period
}

output "kinesis_stream_encryption_type" {
  description = "Encryption type used by the Kinesis stream"
  value       = aws_kinesis_stream.journal_stream.encryption_type
}

# ============================================================================
# IAM Role and Policy Outputs
# ============================================================================

output "iam_role_name" {
  description = "Name of the IAM role for QLDB operations"
  value       = aws_iam_role.qldb_stream_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for QLDB operations"
  value       = aws_iam_role.qldb_stream_role.arn
}

output "iam_role_unique_id" {
  description = "Unique ID of the IAM role"
  value       = aws_iam_role.qldb_stream_role.unique_id
}

# ============================================================================
# CloudWatch Monitoring Outputs
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for QLDB operations"
  value       = aws_cloudwatch_log_group.qldb_operations.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for QLDB operations"
  value       = aws_cloudwatch_log_group.qldb_operations.arn
}

output "read_io_alarm_name" {
  description = "Name of the QLDB read I/O CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.qldb_read_io.alarm_name
}

output "write_io_alarm_name" {
  description = "Name of the QLDB write I/O CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.qldb_write_io.alarm_name
}

output "kinesis_alarm_name" {
  description = "Name of the Kinesis incoming records CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.kinesis_incoming_records.alarm_name
}

# ============================================================================
# Connection Information Outputs
# ============================================================================

output "connection_info" {
  description = "Connection information for the QLDB infrastructure"
  value = {
    ledger_name              = aws_qldb_ledger.financial_ledger.name
    ledger_arn              = aws_qldb_ledger.financial_ledger.arn
    s3_bucket_name          = aws_s3_bucket.journal_exports.id
    kinesis_stream_name     = aws_kinesis_stream.journal_stream.name
    kinesis_stream_arn      = aws_kinesis_stream.journal_stream.arn
    iam_role_arn           = aws_iam_role.qldb_stream_role.arn
    stream_id              = aws_qldb_stream.journal_stream.stream_id
    region                 = data.aws_region.current.name
    account_id             = data.aws_caller_identity.current.account_id
  }
}

# ============================================================================
# Administrative Outputs
# ============================================================================

output "deployment_metadata" {
  description = "Metadata about the deployment"
  value = {
    environment      = var.environment
    application_name = var.application_name
    region          = data.aws_region.current.name
    account_id      = data.aws_caller_identity.current.account_id
    random_suffix   = random_id.suffix.hex
    deployment_time = timestamp()
  }
}

# ============================================================================
# Security and Compliance Outputs
# ============================================================================

output "security_features" {
  description = "Summary of security features enabled"
  value = {
    deletion_protection_enabled = aws_qldb_ledger.financial_ledger.deletion_protection
    s3_encryption_enabled      = true
    kinesis_encryption_enabled = aws_kinesis_stream.journal_stream.encryption_type != ""
    s3_versioning_enabled      = var.s3_versioning_enabled
    s3_public_access_blocked   = true
    iam_least_privilege        = true
    audit_logging_enabled      = true
  }
}

# ============================================================================
# Cost Management Outputs
# ============================================================================

output "cost_optimization" {
  description = "Cost optimization features configured"
  value = {
    s3_lifecycle_enabled           = var.enable_s3_lifecycle
    s3_transition_to_ia_days      = var.s3_transition_to_ia_days
    s3_transition_to_glacier_days = var.s3_transition_to_glacier_days
    s3_transition_to_deep_archive_days = var.s3_transition_to_deep_archive_days
    s3_expiration_days            = var.s3_expiration_days
    kinesis_retention_hours       = var.kinesis_retention_hours
    cloudwatch_log_retention_days = var.log_retention_days
  }
}

# ============================================================================
# CLI Commands for Common Operations
# ============================================================================

output "useful_commands" {
  description = "Useful AWS CLI commands for managing the QLDB infrastructure"
  value = {
    get_ledger_digest = "aws qldb get-digest --name ${aws_qldb_ledger.financial_ledger.name}"
    describe_ledger   = "aws qldb describe-ledger --name ${aws_qldb_ledger.financial_ledger.name}"
    list_streams      = "aws qldb list-journal-kinesis-streams-for-ledger --ledger-name ${aws_qldb_ledger.financial_ledger.name}"
    describe_stream   = "aws qldb describe-journal-kinesis-stream --ledger-name ${aws_qldb_ledger.financial_ledger.name} --stream-id ${aws_qldb_stream.journal_stream.stream_id}"
    export_journal    = "aws qldb export-journal-to-s3 --name ${aws_qldb_ledger.financial_ledger.name} --role-arn ${aws_iam_role.qldb_stream_role.arn} --s3-export-configuration Bucket=${aws_s3_bucket.journal_exports.id},Prefix=exports/,EncryptionConfiguration={ObjectEncryptionType=SSE_S3} --inclusive-start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --exclusive-end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}