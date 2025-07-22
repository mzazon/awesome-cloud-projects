# Outputs for S3 Cross-Region Replication Disaster Recovery Solution
# This file provides important resource information for integration and verification

# S3 Bucket Information
output "source_bucket_name" {
  description = "Name of the source S3 bucket in the primary region"
  value       = aws_s3_bucket.source.id
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket in the primary region"
  value       = aws_s3_bucket.source.arn
}

output "source_bucket_region" {
  description = "Region of the source S3 bucket"
  value       = aws_s3_bucket.source.region
}

output "replica_bucket_name" {
  description = "Name of the replica S3 bucket in the secondary region"
  value       = aws_s3_bucket.replica.id
}

output "replica_bucket_arn" {
  description = "ARN of the replica S3 bucket in the secondary region"
  value       = aws_s3_bucket.replica.arn
}

output "replica_bucket_region" {
  description = "Region of the replica S3 bucket"
  value       = aws_s3_bucket.replica.region
}

# IAM Role Information
output "replication_role_name" {
  description = "Name of the IAM role used for S3 replication"
  value       = aws_iam_role.replication.name
}

output "replication_role_arn" {
  description = "ARN of the IAM role used for S3 replication"
  value       = aws_iam_role.replication.arn
}

# KMS Key Information
output "primary_kms_key_id" {
  description = "ID of the KMS key used for encryption in the primary region"
  value       = var.enable_server_side_encryption ? aws_kms_key.s3_primary[0].key_id : null
}

output "primary_kms_key_arn" {
  description = "ARN of the KMS key used for encryption in the primary region"
  value       = var.enable_server_side_encryption ? aws_kms_key.s3_primary[0].arn : null
}

output "secondary_kms_key_id" {
  description = "ID of the KMS key used for encryption in the secondary region"
  value       = var.enable_server_side_encryption ? aws_kms_key.s3_secondary[0].key_id : null
}

output "secondary_kms_key_arn" {
  description = "ARN of the KMS key used for encryption in the secondary region"
  value       = var.enable_server_side_encryption ? aws_kms_key.s3_secondary[0].arn : null
}

# CloudTrail Information
output "cloudtrail_name" {
  description = "Name of the CloudTrail for audit logging"
  value       = var.enable_cloudtrail ? aws_cloudtrail.s3_audit[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for audit logging"
  value       = var.enable_cloudtrail ? aws_cloudtrail.s3_audit[0].arn : null
}

output "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket used for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].id : null
}

# SNS Topic Information
output "sns_topic_name" {
  description = "Name of the SNS topic for replication alerts"
  value       = var.enable_sns_notifications ? aws_sns_topic.replication_alerts[0].name : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for replication alerts"
  value       = var.enable_sns_notifications ? aws_sns_topic.replication_alerts[0].arn : null
}

# CloudWatch Alarm Information
output "replication_latency_alarm_name" {
  description = "Name of the CloudWatch alarm for replication latency"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.replication_latency[0].alarm_name : null
}

output "replication_failures_alarm_name" {
  description = "Name of the CloudWatch alarm for replication failures"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.replication_failures[0].alarm_name : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for replication monitoring"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_dashboard.replication_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for replication monitoring"
  value       = var.enable_cloudwatch_monitoring ? "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.replication_dashboard[0].dashboard_name}" : null
}

# Replication Configuration Information
output "replication_rules" {
  description = "Information about the replication rules configured"
  value = {
    general_rule = {
      id            = "ReplicateEverything"
      priority      = var.replication_priority
      storage_class = var.replica_storage_class
    }
    critical_rule = {
      id            = "ReplicateCriticalData"
      priority      = var.replication_priority + 1
      prefix        = var.critical_data_prefix
      storage_class = var.critical_replica_storage_class
    }
  }
}

# Disaster Recovery Information
output "disaster_recovery_endpoints" {
  description = "Endpoints for disaster recovery operations"
  value = {
    primary_endpoint   = "s3.${var.primary_region}.amazonaws.com"
    secondary_endpoint = "s3.${var.secondary_region}.amazonaws.com"
    primary_region     = var.primary_region
    secondary_region   = var.secondary_region
  }
}

# Cost and Usage Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost components (for reference)"
  value = {
    note = "Costs depend on actual usage, storage amount, and data transfer"
    components = [
      "S3 Standard storage in primary region",
      "S3 ${var.replica_storage_class} storage in secondary region",
      "Cross-region replication data transfer",
      "CloudWatch metrics and alarms",
      "KMS key usage (if encryption enabled)",
      "CloudTrail logging (if enabled)"
    ]
  }
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the disaster recovery setup"
  value = {
    check_replication_config = "aws s3api get-bucket-replication --bucket ${aws_s3_bucket.source.id} --region ${var.primary_region}"
    upload_test_file         = "aws s3 cp test-file.txt s3://${aws_s3_bucket.source.id}/test/ --region ${var.primary_region}"
    check_replica_file       = "aws s3 ls s3://${aws_s3_bucket.replica.id}/test/ --region ${var.secondary_region}"
    view_cloudwatch_metrics  = "aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name ReplicationLatency --dimensions Name=SourceBucket,Value=${aws_s3_bucket.source.id} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average --region ${var.primary_region}"
  }
}

# Failover Information
output "failover_procedures" {
  description = "Information about disaster recovery failover procedures"
  value = {
    failover_steps = [
      "1. Verify primary region is unavailable",
      "2. Update application configuration to use replica bucket: ${aws_s3_bucket.replica.id}",
      "3. Point applications to secondary region: ${var.secondary_region}",
      "4. Monitor replication lag and data consistency",
      "5. Test application functionality with replica data"
    ]
    failback_steps = [
      "1. Verify primary region is available",
      "2. Ensure all data is synchronized",
      "3. Update application configuration to use source bucket: ${aws_s3_bucket.source.id}",
      "4. Point applications back to primary region: ${var.primary_region}",
      "5. Monitor for any data inconsistencies"
    ]
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    s3_buckets = {
      source_bucket    = aws_s3_bucket.source.id
      replica_bucket   = aws_s3_bucket.replica.id
      cloudtrail_bucket = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].id : null
    }
    iam_resources = {
      replication_role   = aws_iam_role.replication.name
      replication_policy = aws_iam_policy.replication.name
    }
    monitoring_resources = {
      cloudtrail         = var.enable_cloudtrail ? aws_cloudtrail.s3_audit[0].name : null
      sns_topic          = var.enable_sns_notifications ? aws_sns_topic.replication_alerts[0].name : null
      latency_alarm      = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.replication_latency[0].alarm_name : null
      failures_alarm     = var.enable_cloudwatch_monitoring ? aws_cloudwatch_metric_alarm.replication_failures[0].alarm_name : null
      dashboard          = var.enable_cloudwatch_monitoring ? aws_cloudwatch_dashboard.replication_dashboard[0].dashboard_name : null
    }
    encryption_resources = {
      primary_kms_key   = var.enable_server_side_encryption ? aws_kms_key.s3_primary[0].key_id : null
      secondary_kms_key = var.enable_server_side_encryption ? aws_kms_key.s3_secondary[0].key_id : null
    }
  }
}