# S3 Bucket Outputs
output "bucket_name" {
  description = "Name of the S3 bucket created for data archiving"
  value       = aws_s3_bucket.data_archiving_bucket.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.data_archiving_bucket.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.data_archiving_bucket.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.data_archiving_bucket.bucket_regional_domain_name
}

# Lifecycle Configuration Outputs
output "lifecycle_rules" {
  description = "Summary of lifecycle rules configured on the bucket"
  value = {
    document_archiving = {
      prefix                    = "documents/"
      ia_transition_days       = var.document_ia_transition_days
      glacier_transition_days  = var.document_glacier_transition_days
      deep_archive_transition_days = var.document_deep_archive_transition_days
    }
    log_archiving = {
      prefix                  = "logs/"
      ia_transition_days     = var.log_ia_transition_days
      glacier_transition_days = var.log_glacier_transition_days
      expiration_days        = var.log_expiration_days
    }
    backup_archiving = {
      prefix                  = "backups/"
      ia_transition_days     = var.backup_ia_transition_days
      glacier_transition_days = var.backup_glacier_transition_days
    }
    media_intelligent_tiering = {
      prefix = "media/"
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

# Intelligent Tiering Configuration
output "intelligent_tiering_config" {
  description = "Intelligent tiering configuration details"
  value = var.enable_intelligent_tiering ? {
    enabled                   = true
    prefix                   = "media/"
    archive_access_days      = var.intelligent_tiering_archive_days
    deep_archive_access_days = var.intelligent_tiering_deep_archive_days
  } : {
    enabled = false
  }
}

# Analytics Configuration
output "analytics_configuration" {
  description = "S3 Analytics configuration status"
  value = {
    enabled           = var.enable_s3_analytics
    document_analytics = var.enable_s3_analytics ? "documents/" : "disabled"
    reports_prefix    = "analytics-reports/documents/"
  }
}

# Inventory Configuration
output "inventory_configuration" {
  description = "S3 Inventory configuration details"
  value = {
    enabled           = var.enable_s3_inventory
    frequency         = var.inventory_frequency
    reports_prefix    = "inventory-reports/"
    included_fields   = ["Size", "LastModifiedDate", "StorageClass", "IntelligentTieringAccessTier"]
  }
}

# IAM Role Outputs
output "lifecycle_role_arn" {
  description = "ARN of the IAM role for lifecycle management"
  value       = var.create_lifecycle_role ? aws_iam_role.lifecycle_role[0].arn : null
}

output "lifecycle_role_name" {
  description = "Name of the IAM role for lifecycle management"
  value       = var.create_lifecycle_role ? aws_iam_role.lifecycle_role[0].name : null
}

output "lifecycle_policy_arn" {
  description = "ARN of the IAM policy for lifecycle management"
  value       = var.create_lifecycle_role ? aws_iam_policy.lifecycle_policy[0].arn : null
}

# CloudWatch Monitoring Outputs
output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring"
  value = var.enable_cloudwatch_monitoring ? {
    storage_cost_alarm = {
      name      = aws_cloudwatch_metric_alarm.storage_cost_alarm[0].alarm_name
      threshold = var.storage_cost_threshold
    }
    object_count_alarm = {
      name      = aws_cloudwatch_metric_alarm.object_count_alarm[0].alarm_name
      threshold = var.object_count_threshold
    }
  } : {
    enabled = false
  }
}

# Sample Data Objects
output "sample_objects" {
  description = "Sample objects created for demonstration"
  value = {
    document = aws_s3_object.sample_document.key
    log      = aws_s3_object.sample_log.key
    backup   = aws_s3_object.sample_backup.key
    media    = aws_s3_object.sample_media.key
  }
}

# Cost Optimization Summary
output "cost_optimization_features" {
  description = "Summary of cost optimization features enabled"
  value = {
    lifecycle_policies    = "Enabled for all data types"
    intelligent_tiering  = var.enable_intelligent_tiering ? "Enabled for media files" : "Disabled"
    analytics           = var.enable_s3_analytics ? "Enabled for documents" : "Disabled"
    inventory           = var.enable_s3_inventory ? "Enabled (${var.inventory_frequency})" : "Disabled"
    monitoring          = var.enable_cloudwatch_monitoring ? "CloudWatch alarms enabled" : "Disabled"
    versioning          = var.enable_versioning ? "Enabled" : "Disabled"
    encryption          = var.enable_server_side_encryption ? "Enabled (AES256)" : "Disabled"
  }
}

# Storage Class Transition Summary
output "storage_class_transitions" {
  description = "Summary of storage class transitions by data type"
  value = {
    documents = "Standard -> IA (${var.document_ia_transition_days}d) -> Glacier (${var.document_glacier_transition_days}d) -> Deep Archive (${var.document_deep_archive_transition_days}d)"
    logs      = "Standard -> IA (${var.log_ia_transition_days}d) -> Glacier (${var.log_glacier_transition_days}d) -> Deep Archive (${var.log_glacier_transition_days + 60}d) -> Expired (${var.log_expiration_days}d)"
    backups   = "Standard -> IA (${var.backup_ia_transition_days}d) -> Glacier (${var.backup_glacier_transition_days}d)"
    media     = "Intelligent Tiering -> Archive Access (${var.intelligent_tiering_archive_days}d) -> Deep Archive Access (${var.intelligent_tiering_deep_archive_days}d)"
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployed infrastructure"
  value = {
    aws_region     = data.aws_region.current.name
    aws_account_id = data.aws_caller_identity.current.account_id
    environment    = var.environment
    bucket_name    = aws_s3_bucket.data_archiving_bucket.id
    created_at     = timestamp()
  }
}

# Commands for Testing and Validation
output "testing_commands" {
  description = "AWS CLI commands for testing the lifecycle configuration"
  value = {
    list_objects = "aws s3 ls s3://${aws_s3_bucket.data_archiving_bucket.id} --recursive"
    check_lifecycle = "aws s3api get-bucket-lifecycle-configuration --bucket ${aws_s3_bucket.data_archiving_bucket.id}"
    check_intelligent_tiering = var.enable_intelligent_tiering ? "aws s3api get-bucket-intelligent-tiering-configuration --bucket ${aws_s3_bucket.data_archiving_bucket.id} --id MediaIntelligentTieringConfig" : "N/A - Intelligent Tiering disabled"
    upload_test_file = "echo 'Test content' | aws s3 cp - s3://${aws_s3_bucket.data_archiving_bucket.id}/documents/test-file.txt"
    check_cloudwatch_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name BucketSizeBytes --dimensions Name=BucketName,Value=${aws_s3_bucket.data_archiving_bucket.id} Name=StorageType,Value=StandardStorage --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 3600 --statistics Sum"
  }
}