# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "source_bucket_name" {
  description = "Name of the source S3 bucket"
  value       = aws_s3_bucket.source.id
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "source_bucket_domain_name" {
  description = "Domain name of the source S3 bucket"
  value       = aws_s3_bucket.source.bucket_domain_name
}

output "source_bucket_region" {
  description = "Region of the source S3 bucket"
  value       = aws_s3_bucket.source.region
}

output "destination_bucket_1_name" {
  description = "Name of the first destination S3 bucket"
  value       = aws_s3_bucket.dest1.id
}

output "destination_bucket_1_arn" {
  description = "ARN of the first destination S3 bucket"
  value       = aws_s3_bucket.dest1.arn
}

output "destination_bucket_1_region" {
  description = "Region of the first destination S3 bucket"
  value       = aws_s3_bucket.dest1.region
}

output "destination_bucket_2_name" {
  description = "Name of the second destination S3 bucket"
  value       = aws_s3_bucket.dest2.id
}

output "destination_bucket_2_arn" {
  description = "ARN of the second destination S3 bucket"
  value       = aws_s3_bucket.dest2.arn
}

output "destination_bucket_2_region" {
  description = "Region of the second destination S3 bucket"
  value       = aws_s3_bucket.dest2.region
}

# =============================================================================
# KMS KEY OUTPUTS
# =============================================================================

output "source_kms_key_id" {
  description = "ID of the source KMS key"
  value       = aws_kms_key.source.key_id
}

output "source_kms_key_arn" {
  description = "ARN of the source KMS key"
  value       = aws_kms_key.source.arn
}

output "source_kms_alias_name" {
  description = "Alias name of the source KMS key"
  value       = aws_kms_alias.source.name
}

output "destination_kms_key_1_id" {
  description = "ID of the first destination KMS key"
  value       = aws_kms_key.dest1.key_id
}

output "destination_kms_key_1_arn" {
  description = "ARN of the first destination KMS key"
  value       = aws_kms_key.dest1.arn
}

output "destination_kms_alias_1_name" {
  description = "Alias name of the first destination KMS key"
  value       = aws_kms_alias.dest1.name
}

output "destination_kms_key_2_id" {
  description = "ID of the second destination KMS key"
  value       = aws_kms_key.dest2.key_id
}

output "destination_kms_key_2_arn" {
  description = "ARN of the second destination KMS key"
  value       = aws_kms_key.dest2.arn
}

output "destination_kms_alias_2_name" {
  description = "Alias name of the second destination KMS key"
  value       = aws_kms_alias.dest2.name
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "replication_role_name" {
  description = "Name of the S3 replication IAM role"
  value       = aws_iam_role.replication.name
}

output "replication_role_arn" {
  description = "ARN of the S3 replication IAM role"
  value       = aws_iam_role.replication.arn
}

output "replication_role_id" {
  description = "ID of the S3 replication IAM role"
  value       = aws_iam_role.replication.id
}

# =============================================================================
# REPLICATION CONFIGURATION OUTPUTS
# =============================================================================

output "replication_configuration_id" {
  description = "ID of the S3 bucket replication configuration"
  value       = aws_s3_bucket_replication_configuration.source.id
}

output "replication_time_control_minutes" {
  description = "Replication Time Control setting in minutes"
  value       = var.replication_time_control_minutes
}

output "destination_storage_class" {
  description = "Storage class used for replicated objects"
  value       = var.destination_storage_class
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for replication alerts"
  value       = var.enable_cloudwatch_monitoring ? aws_sns_topic.alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for replication alerts"
  value       = var.enable_cloudwatch_monitoring ? aws_sns_topic.alerts[0].name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for replication monitoring"
  value = var.enable_cloudwatch_dashboard ? "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.replication[0].dashboard_name}" : null
}

output "replication_failure_alarm_arn" {
  description = "ARN of the replication failure CloudWatch alarm"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.replication_failure[0].arn : null
}

output "replication_latency_alarm_arn" {
  description = "ARN of the replication latency CloudWatch alarm"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.replication_latency[0].arn : null
}

# =============================================================================
# CLOUDTRAIL OUTPUTS
# =============================================================================

output "cloudtrail_name" {
  description = "Name of the CloudTrail for audit logging"
  value       = var.enable_cloudtrail ? aws_cloudtrail.audit[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for audit logging"
  value       = var.enable_cloudtrail ? aws_cloudtrail.audit[0].arn : null
}

# =============================================================================
# CONFIGURATION SUMMARY OUTPUTS
# =============================================================================

output "regions_configured" {
  description = "List of regions configured for multi-region replication"
  value = [
    var.primary_region,
    var.secondary_region,
    var.tertiary_region
  ]
}

output "intelligent_tiering_enabled" {
  description = "Whether S3 Intelligent Tiering is enabled"
  value       = var.enable_intelligent_tiering
}

output "lifecycle_policy_enabled" {
  description = "Whether S3 lifecycle policies are enabled"
  value       = var.enable_lifecycle_policy
}

output "bucket_key_enabled" {
  description = "Whether S3 Bucket Key optimization is enabled"
  value       = var.enable_bucket_key
}

output "versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.enable_versioning
}

output "public_access_blocked" {
  description = "Whether S3 bucket public access is blocked"
  value       = var.enable_bucket_public_access_block
}

output "ssl_requests_only" {
  description = "Whether SSL/TLS requests are enforced"
  value       = var.enable_ssl_requests_only
}

# =============================================================================
# OPERATIONAL OUTPUTS
# =============================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_timestamp" {
  description = "Timestamp when resources were deployed"
  value       = timestamp()
}

# =============================================================================
# TESTING AND VALIDATION OUTPUTS
# =============================================================================

output "test_commands" {
  description = "Commands to test the multi-region replication setup"
  value = {
    upload_test_file = "aws s3 cp test.txt s3://${aws_s3_bucket.source.id}/test/"
    check_replication_dest1 = "aws s3 ls s3://${aws_s3_bucket.dest1.id}/test/ --region ${var.secondary_region}"
    check_replication_dest2 = "aws s3 ls s3://${aws_s3_bucket.dest2.id}/test/ --region ${var.tertiary_region}"
    check_encryption_status = "aws s3api head-object --bucket ${aws_s3_bucket.source.id} --key test/test.txt --query ServerSideEncryption"
    view_replication_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name ReplicationLatency --dimensions Name=SourceBucket,Value=${aws_s3_bucket.source.id} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average"
  }
}

output "cleanup_commands" {
  description = "Commands to clean up test data and resources"
  value = {
    remove_test_objects_source = "aws s3 rm s3://${aws_s3_bucket.source.id} --recursive"
    remove_test_objects_dest1 = "aws s3 rm s3://${aws_s3_bucket.dest1.id} --recursive --region ${var.secondary_region}"
    remove_test_objects_dest2 = "aws s3 rm s3://${aws_s3_bucket.dest2.id} --recursive --region ${var.tertiary_region}"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}

# =============================================================================
# COST OPTIMIZATION OUTPUTS
# =============================================================================

output "cost_optimization_features" {
  description = "Cost optimization features enabled"
  value = {
    intelligent_tiering = var.enable_intelligent_tiering
    lifecycle_policies = var.enable_lifecycle_policy
    bucket_key_optimization = var.enable_bucket_key
    destination_storage_class = var.destination_storage_class
    lifecycle_transitions = var.enable_lifecycle_policy ? {
      to_ia_days = var.transition_to_ia_days
      to_glacier_days = var.transition_to_glacier_days
      to_deep_archive_days = var.transition_to_deep_archive_days
    } : null
  }
}

# =============================================================================
# SECURITY OUTPUTS
# =============================================================================

output "security_features" {
  description = "Security features enabled"
  value = {
    kms_encryption = "Customer-managed keys"
    ssl_only_access = var.enable_ssl_requests_only
    public_access_blocked = var.enable_bucket_public_access_block
    bucket_versioning = var.enable_versioning
    cloudtrail_logging = var.enable_cloudtrail
    key_rotation_enabled = true
    multi_region_keys = true
  }
}