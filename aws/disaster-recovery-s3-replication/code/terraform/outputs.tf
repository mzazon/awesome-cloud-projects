# ==========================================
# S3 BUCKET OUTPUTS
# ==========================================

output "source_bucket_id" {
  description = "ID of the source S3 bucket"
  value       = aws_s3_bucket.source.id
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "source_bucket_name" {
  description = "Name of the source S3 bucket"
  value       = aws_s3_bucket.source.bucket
}

output "source_bucket_region" {
  description = "Region of the source S3 bucket"
  value       = aws_s3_bucket.source.region
}

output "destination_bucket_id" {
  description = "ID of the destination S3 bucket"
  value       = aws_s3_bucket.destination.id
}

output "destination_bucket_arn" {
  description = "ARN of the destination S3 bucket"
  value       = aws_s3_bucket.destination.arn
}

output "destination_bucket_name" {
  description = "Name of the destination S3 bucket"
  value       = aws_s3_bucket.destination.bucket
}

output "destination_bucket_region" {
  description = "Region of the destination S3 bucket"
  value       = aws_s3_bucket.destination.region
}

# ==========================================
# IAM ROLE OUTPUTS
# ==========================================

output "replication_role_arn" {
  description = "ARN of the S3 replication IAM role"
  value       = aws_iam_role.replication.arn
}

output "replication_role_name" {
  description = "Name of the S3 replication IAM role"
  value       = aws_iam_role.replication.name
}

# ==========================================
# REPLICATION CONFIGURATION OUTPUTS
# ==========================================

output "replication_configuration_id" {
  description = "ID of the S3 replication configuration"
  value       = aws_s3_bucket_replication_configuration.replication.id
}

output "replication_rule_id" {
  description = "ID of the replication rule"
  value       = "disaster-recovery-replication"
}

output "replication_storage_class" {
  description = "Storage class used for replicated objects"
  value       = var.replication_storage_class
}

# ==========================================
# MONITORING AND ALERTING OUTPUTS
# ==========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.alerts[0].arn : null
}

output "cloudwatch_alarm_names" {
  description = "Names of the CloudWatch alarms monitoring replication"
  value = var.enable_cloudwatch_alarms ? [
    aws_cloudwatch_metric_alarm.replication_latency[0].alarm_name,
    aws_cloudwatch_metric_alarm.replication_failures[0].alarm_name
  ] : []
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail for S3 API logging (if enabled)"
  value       = var.enable_cloudtrail ? aws_cloudtrail.s3_trail[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for S3 API logging (if enabled)"
  value       = var.enable_cloudtrail ? aws_cloudtrail.s3_trail[0].arn : null
}

# ==========================================
# COST ESTIMATION OUTPUTS
# ==========================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for cross-region replication (informational)"
  value = {
    data_transfer_per_gb     = "$0.025"
    storage_cost_depends_on  = "Data volume and storage class"
    note                     = "Actual costs depend on data volume, request patterns, and storage classes used"
  }
}

# ==========================================
# CONFIGURATION SUMMARY OUTPUTS
# ==========================================

output "disaster_recovery_summary" {
  description = "Summary of the disaster recovery configuration"
  value = {
    primary_region               = var.primary_region
    dr_region                   = var.dr_region
    source_bucket               = aws_s3_bucket.source.bucket
    destination_bucket          = aws_s3_bucket.destination.bucket
    replication_enabled         = true
    versioning_enabled          = true
    encryption_enabled          = var.enable_bucket_encryption
    cloudtrail_enabled          = var.enable_cloudtrail
    cloudwatch_alarms_enabled   = var.enable_cloudwatch_alarms
    lifecycle_policies_enabled  = var.enable_lifecycle_policies
    public_access_blocked       = var.enable_public_access_block
    notification_email          = var.notification_email != "" ? var.notification_email : "Not configured"
  }
}

# ==========================================
# VALIDATION AND TESTING OUTPUTS
# ==========================================

output "aws_cli_commands" {
  description = "Useful AWS CLI commands for testing and validation"
  value = {
    check_replication_config = "aws s3api get-bucket-replication --bucket ${aws_s3_bucket.source.bucket} --region ${var.primary_region}"
    test_file_upload        = "aws s3 cp test-file.txt s3://${aws_s3_bucket.source.bucket}/test-file.txt --region ${var.primary_region}"
    verify_replication      = "aws s3 ls s3://${aws_s3_bucket.destination.bucket}/ --region ${var.dr_region}"
    check_metrics          = "aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name ReplicationLatency --dimensions Name=SourceBucket,Value=${aws_s3_bucket.source.bucket} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average --region ${var.primary_region}"
  }
}

# ==========================================
# SECURITY AND COMPLIANCE OUTPUTS
# ==========================================

output "security_features" {
  description = "Security features enabled in this configuration"
  value = {
    bucket_encryption        = var.enable_bucket_encryption ? "Enabled" : "Disabled"
    public_access_block     = var.enable_public_access_block ? "Enabled" : "Disabled"
    versioning             = "Enabled (Required for replication)"
    cloudtrail_logging     = var.enable_cloudtrail ? "Enabled" : "Disabled"
    iam_least_privilege    = "Enabled (Replication role has minimal required permissions)"
    kms_encryption         = var.kms_key_id != "" ? "Customer-managed KMS key" : "S3-managed encryption"
  }
}

# ==========================================
# NEXT STEPS OUTPUTS
# ==========================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm SNS email subscription if notification email was provided",
    "2. Test replication by uploading a file to the source bucket",
    "3. Monitor CloudWatch alarms for replication health",
    "4. Review CloudTrail logs for audit purposes",
    "5. Consider implementing S3 Transfer Acceleration for large files",
    "6. Set up automated disaster recovery testing procedures",
    "7. Review and adjust lifecycle policies based on your retention requirements"
  ]
}