# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "backup_bucket_name" {
  description = "Name of the S3 bucket for backup and archive storage"
  value       = aws_s3_bucket.backup_archive.bucket
}

output "backup_bucket_arn" {
  description = "ARN of the S3 bucket for backup and archive storage"
  value       = aws_s3_bucket.backup_archive.arn
}

output "backup_bucket_id" {
  description = "ID of the S3 bucket for backup and archive storage"
  value       = aws_s3_bucket.backup_archive.id
}

output "backup_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.backup_archive.bucket_domain_name
}

output "backup_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.backup_archive.bucket_regional_domain_name
}

# ============================================================================
# LIFECYCLE POLICY OUTPUTS
# ============================================================================

output "lifecycle_policy_id" {
  description = "ID of the S3 bucket lifecycle configuration"
  value       = aws_s3_bucket_lifecycle_configuration.backup_archive.id
}

output "backup_transition_schedule" {
  description = "Backup data transition schedule in days"
  value = {
    standard_to_ia          = var.backup_transition_to_ia_days
    ia_to_glacier_ir        = var.backup_transition_to_glacier_ir_days
    glacier_ir_to_glacier   = var.backup_transition_to_glacier_days
    glacier_to_deep_archive = var.backup_transition_to_deep_archive_days
  }
}

output "logs_retention_schedule" {
  description = "Log data retention and transition schedule in days"
  value = {
    standard_to_ia = var.logs_transition_to_ia_days
    expiration     = var.logs_expiration_days
  }
}

output "documents_transition_schedule" {
  description = "Document data transition schedule in days"
  value = {
    standard_to_glacier_ir  = var.documents_transition_to_glacier_ir_days
    glacier_ir_to_glacier   = var.documents_transition_to_glacier_days
    glacier_to_deep_archive = var.documents_transition_to_deep_archive_days
  }
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "glacier_operations_role_arn" {
  description = "ARN of the IAM role for Glacier operations"
  value       = aws_iam_role.glacier_operations.arn
}

output "glacier_operations_role_name" {
  description = "Name of the IAM role for Glacier operations"
  value       = aws_iam_role.glacier_operations.name
}

output "glacier_operations_policy_arn" {
  description = "ARN of the custom Glacier operations policy"
  value       = aws_iam_policy.glacier_operations.arn
}

# ============================================================================
# GLACIER DATA RETRIEVAL POLICY OUTPUTS
# ============================================================================

output "glacier_retrieval_policy_account_id" {
  description = "AWS account ID for the Glacier data retrieval policy"
  value       = aws_glacier_data_retrieval_policy.cost_control.account_id
}

output "glacier_retrieval_bytes_per_hour" {
  description = "Maximum bytes per hour allowed for Glacier data retrieval"
  value       = var.glacier_retrieval_bytes_per_hour
}

# ============================================================================
# CLOUDWATCH MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for lifecycle transitions"
  value       = var.enable_cost_monitoring ? aws_cloudwatch_log_group.lifecycle_transitions[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for lifecycle transitions"
  value       = var.enable_cost_monitoring ? aws_cloudwatch_log_group.lifecycle_transitions[0].arn : null
}

output "cost_alarm_name" {
  description = "Name of the CloudWatch cost monitoring alarm"
  value       = var.enable_cost_monitoring ? aws_cloudwatch_metric_alarm.storage_cost_alarm[0].alarm_name : null
}

output "cost_alarm_arn" {
  description = "ARN of the CloudWatch cost monitoring alarm"
  value       = var.enable_cost_monitoring ? aws_cloudwatch_metric_alarm.storage_cost_alarm[0].arn : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost alerts"
  value       = var.enable_cost_monitoring && var.notification_email != "" ? aws_sns_topic.cost_alerts[0].arn : null
}

# ============================================================================
# CONFIGURATION SUMMARY OUTPUTS
# ============================================================================

output "bucket_configuration_summary" {
  description = "Summary of bucket configuration settings"
  value = {
    bucket_name           = aws_s3_bucket.backup_archive.bucket
    versioning_enabled    = var.enable_versioning
    encryption_enabled    = true
    public_access_blocked = true
    lifecycle_rules_count = 3
    cost_monitoring       = var.enable_cost_monitoring
  }
}

output "storage_cost_estimates" {
  description = "Estimated monthly storage costs for different storage classes (per GB)"
  value = {
    note                    = "Costs are estimates and vary by region. Check AWS pricing for current rates."
    s3_standard            = "~$0.023/GB/month"
    s3_standard_ia         = "~$0.0125/GB/month"
    s3_glacier_ir          = "~$0.004/GB/month"
    s3_glacier             = "~$0.0036/GB/month"
    s3_deep_archive        = "~$0.00099/GB/month"
    retrieval_costs_apply  = "Yes - varies by storage class and retrieval speed"
  }
}

output "data_access_patterns" {
  description = "Recommended data access patterns for each storage class"
  value = {
    s3_standard = {
      description    = "Frequently accessed data"
      access_pattern = "Multiple times per month"
      retrieval_time = "Immediate"
    }
    s3_standard_ia = {
      description    = "Infrequently accessed data"
      access_pattern = "Once per month or less"
      retrieval_time = "Immediate"
    }
    s3_glacier_ir = {
      description    = "Archive data with instant retrieval needs"
      access_pattern = "Once per quarter"
      retrieval_time = "Immediate"
    }
    s3_glacier = {
      description    = "Archive data for backup and disaster recovery"
      access_pattern = "Once per year or less"
      retrieval_time = "1-5 minutes to 12 hours"
    }
    s3_deep_archive = {
      description    = "Long-term archive and compliance"
      access_pattern = "Rarely accessed"
      retrieval_time = "12-48 hours"
    }
  }
}

# ============================================================================
# DEPLOYMENT INFORMATION
# ============================================================================

output "deployment_info" {
  description = "Information about the deployed infrastructure"
  value = {
    aws_region           = data.aws_region.current.name
    aws_account_id       = data.aws_caller_identity.current.account_id
    terraform_workspace  = terraform.workspace
    deployment_timestamp = timestamp()
    project_name         = var.project_name
    environment          = var.environment
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    step_1 = "Upload sample data to test lifecycle policies: aws s3 cp file.txt s3://${aws_s3_bucket.backup_archive.bucket}/backups/"
    step_2 = "Tag documents for archive lifecycle: aws s3api put-object-tagging --bucket ${aws_s3_bucket.backup_archive.bucket} --key documents/file.pdf --tagging 'TagSet=[{Key=DataClass,Value=Archive}]'"
    step_3 = "Monitor lifecycle transitions in CloudWatch logs: aws logs describe-log-groups --log-group-name-prefix /aws/s3/"
    step_4 = "Test restore process: aws s3api restore-object --bucket ${aws_s3_bucket.backup_archive.bucket} --key archived-file.txt --restore-request Days=7,GlacierJobParameters='{Tier=Standard}'"
    step_5 = "Review cost reports in AWS Cost Explorer to track storage optimization"
  }
}

# ============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ============================================================================

output "security_features" {
  description = "Security features enabled for the backup and archive solution"
  value = {
    encryption_at_rest      = "AES-256 server-side encryption enabled"
    encryption_in_transit   = "HTTPS/TLS enforced"
    public_access_blocked   = "All public access blocked"
    versioning_enabled      = var.enable_versioning
    mfa_delete_protection   = var.enable_mfa_delete
    iam_least_privilege     = "Role-based access with minimal permissions"
    cost_controls          = "Data retrieval limits configured"
    audit_logging          = var.enable_cost_monitoring ? "CloudWatch logging enabled" : "CloudWatch logging disabled"
  }
}

output "compliance_features" {
  description = "Compliance and governance features"
  value = {
    data_retention_policies = "Automated lifecycle management with defined retention periods"
    audit_trail            = "CloudTrail integration for API calls"
    cost_monitoring        = var.enable_cost_monitoring ? "Enabled with threshold alerts" : "Disabled"
    data_classification    = "Tag-based data classification for different retention requirements"
    disaster_recovery      = "Multi-AZ durability with 99.999999999% (11 9's) durability"
    regulatory_compliance  = "Supports various compliance frameworks (SOX, GDPR, HIPAA)"
  }
}