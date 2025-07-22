# =============================================================================
# Outputs for S3 Cross-Region Replication with Encryption and Access Controls
# =============================================================================

# =============================================================================
# S3 Bucket Information
# =============================================================================

output "source_bucket_name" {
  description = "Name of the source S3 bucket"
  value       = aws_s3_bucket.source.bucket
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "source_bucket_region" {
  description = "Region of the source S3 bucket"
  value       = aws_s3_bucket.source.region
}

output "destination_bucket_name" {
  description = "Name of the destination S3 bucket"
  value       = aws_s3_bucket.destination.bucket
}

output "destination_bucket_arn" {
  description = "ARN of the destination S3 bucket"
  value       = aws_s3_bucket.destination.arn
}

output "destination_bucket_region" {
  description = "Region of the destination S3 bucket"
  value       = aws_s3_bucket.destination.region
}

# =============================================================================
# KMS Key Information
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
  description = "Alias name for the source KMS key"
  value       = aws_kms_alias.source.name
}

output "destination_kms_key_id" {
  description = "ID of the destination KMS key"
  value       = aws_kms_key.destination.key_id
}

output "destination_kms_key_arn" {
  description = "ARN of the destination KMS key"
  value       = aws_kms_key.destination.arn
}

output "destination_kms_alias_name" {
  description = "Alias name for the destination KMS key"
  value       = aws_kms_alias.destination.name
}

# =============================================================================
# IAM Role Information
# =============================================================================

output "replication_role_name" {
  description = "Name of the IAM role used for replication"
  value       = aws_iam_role.replication.name
}

output "replication_role_arn" {
  description = "ARN of the IAM role used for replication"
  value       = aws_iam_role.replication.arn
}

output "replication_policy_arn" {
  description = "ARN of the IAM policy for replication"
  value       = aws_iam_policy.replication.arn
}

# =============================================================================
# Replication Configuration
# =============================================================================

output "replication_configuration_status" {
  description = "Status of the replication configuration"
  value       = aws_s3_bucket_replication_configuration.replication.rule[0].status
}

output "replication_rule_id" {
  description = "ID of the replication rule"
  value       = aws_s3_bucket_replication_configuration.replication.rule[0].id
}

output "replication_storage_class" {
  description = "Storage class used for replicated objects"
  value       = aws_s3_bucket_replication_configuration.replication.rule[0].destination[0].storage_class
}

# =============================================================================
# Monitoring Information
# =============================================================================

output "replication_latency_alarm_name" {
  description = "Name of the CloudWatch alarm for replication latency"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.replication_latency[0].alarm_name : null
}

output "source_bucket_size_alarm_name" {
  description = "Name of the CloudWatch alarm for source bucket size"
  value       = var.enable_monitoring && var.enable_size_monitoring ? aws_cloudwatch_metric_alarm.source_bucket_size[0].alarm_name : null
}

output "metrics_configuration_name" {
  description = "Name of the S3 metrics configuration"
  value       = var.enable_monitoring ? aws_s3_bucket_metrics_configuration.source_metrics[0].name : null
}

# =============================================================================
# CLI Commands for Testing
# =============================================================================

output "test_upload_command" {
  description = "AWS CLI command to test uploading a file to the source bucket"
  value = <<-EOT
    # Create a test file
    echo "Test data for replication - $(date)" > test-file.txt
    
    # Upload to source bucket with KMS encryption
    aws s3 cp test-file.txt s3://${aws_s3_bucket.source.bucket}/test-file.txt \
        --sse aws:kms \
        --sse-kms-key-id ${aws_kms_key.source.key_id} \
        --region ${var.source_region}
  EOT
}

output "test_replication_command" {
  description = "AWS CLI command to verify replication to destination bucket"
  value = <<-EOT
    # Wait for replication (typically 2-15 minutes)
    sleep 30
    
    # Check if object exists in destination bucket
    aws s3 ls s3://${aws_s3_bucket.destination.bucket}/ \
        --region ${var.destination_region}
    
    # Verify encryption on replicated object
    aws s3api head-object \
        --bucket ${aws_s3_bucket.destination.bucket} \
        --key test-file.txt \
        --region ${var.destination_region} \
        --query '[ServerSideEncryption,SSEKMSKeyId]' \
        --output table
  EOT
}

output "monitor_replication_command" {
  description = "AWS CLI command to monitor replication metrics"
  value = <<-EOT
    # Check replication status on source object
    aws s3api head-object \
        --bucket ${aws_s3_bucket.source.bucket} \
        --key test-file.txt \
        --region ${var.source_region} \
        --query 'ReplicationStatus' \
        --output text
    
    # Get replication metrics from CloudWatch
    aws cloudwatch get-metric-statistics \
        --namespace AWS/S3 \
        --metric-name NumberOfObjectsPendingReplication \
        --dimensions Name=SourceBucket,Value=${aws_s3_bucket.source.bucket} Name=DestinationBucket,Value=${aws_s3_bucket.destination.bucket} \
        --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 300 \
        --statistics Sum \
        --region ${var.source_region}
  EOT
}

# =============================================================================
# Security and Compliance Information
# =============================================================================

output "security_features_enabled" {
  description = "List of security features enabled in this configuration"
  value = {
    bucket_encryption          = "KMS encryption with separate keys per region"
    bucket_versioning         = "Enabled on both buckets"
    public_access_blocked      = var.enable_public_access_block
    bucket_policies_enforced   = var.enable_bucket_policies
    secure_transport_required  = "HTTPS required for all bucket operations"
    kms_key_rotation          = "Automatic key rotation enabled"
    least_privilege_iam       = "Replication role follows least privilege principle"
    cross_region_encryption   = "Objects re-encrypted with destination region key"
  }
}

output "cost_optimization_features" {
  description = "Cost optimization features configured"
  value = {
    bucket_key_enabled        = var.enable_bucket_key
    replication_storage_class = var.replication_storage_class
    intelligent_tiering      = var.enable_intelligent_tiering
    kms_cost_optimization    = "Bucket key reduces KMS API calls"
  }
}

# =============================================================================
# Resource Summary
# =============================================================================

output "resource_summary" {
  description = "Summary of all resources created"
  value = {
    s3_buckets           = 2
    kms_keys            = 2
    kms_aliases         = 2
    iam_roles           = 1
    iam_policies        = 1
    replication_rules   = 1
    cloudwatch_alarms   = var.enable_monitoring ? (var.enable_size_monitoring ? 2 : 1) : 0
    total_regions_used  = 2
  }
}

# =============================================================================
# Validation Commands
# =============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_source_bucket = "aws s3api head-bucket --bucket ${aws_s3_bucket.source.bucket} --region ${var.source_region}"
    check_dest_bucket   = "aws s3api head-bucket --bucket ${aws_s3_bucket.destination.bucket} --region ${var.destination_region}"
    check_replication   = "aws s3api get-bucket-replication --bucket ${aws_s3_bucket.source.bucket} --region ${var.source_region}"
    check_source_encryption = "aws s3api get-bucket-encryption --bucket ${aws_s3_bucket.source.bucket} --region ${var.source_region}"
    check_dest_encryption = "aws s3api get-bucket-encryption --bucket ${aws_s3_bucket.destination.bucket} --region ${var.destination_region}"
  }
}

# =============================================================================
# Cleanup Commands
# =============================================================================

output "cleanup_commands" {
  description = "Commands to clean up resources (run before terraform destroy)"
  value = {
    empty_source_bucket = "aws s3 rm s3://${aws_s3_bucket.source.bucket}/ --recursive --region ${var.source_region}"
    empty_dest_bucket   = "aws s3 rm s3://${aws_s3_bucket.destination.bucket}/ --recursive --region ${var.destination_region}"
    remove_replication  = "aws s3api delete-bucket-replication --bucket ${aws_s3_bucket.source.bucket} --region ${var.source_region}"
    warning            = "⚠️  Empty buckets before running 'terraform destroy' to avoid errors"
  }
}