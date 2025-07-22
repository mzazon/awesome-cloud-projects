# =============================================================================
# Output Values for S3 Storage Cost Optimization
# =============================================================================
# This file defines all output values from the S3 storage cost optimization
# solution, providing essential information for verification, integration,
# and operational management of the deployed infrastructure.

# =============================================================================
# S3 Bucket Information
# =============================================================================
output "bucket_name" {
  description = "Name of the S3 bucket created for cost optimization"
  value       = aws_s3_bucket.storage_optimization.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket created for cost optimization"
  value       = aws_s3_bucket.storage_optimization.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.storage_optimization.bucket_domain_name
}

output "bucket_hosted_zone_id" {
  description = "Hosted zone ID for the S3 bucket"
  value       = aws_s3_bucket.storage_optimization.hosted_zone_id
}

output "bucket_region" {
  description = "AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.storage_optimization.region
}

output "bucket_website_endpoint" {
  description = "Website endpoint for the S3 bucket (if configured)"
  value       = aws_s3_bucket.storage_optimization.website_endpoint
}

# =============================================================================
# Storage Analytics Information
# =============================================================================
output "analytics_configuration_id" {
  description = "ID of the storage analytics configuration"
  value       = aws_s3_bucket_analytics_configuration.storage_analytics.name
}

output "analytics_filter_prefix" {
  description = "Prefix used for storage analytics filtering"
  value       = var.analytics_prefix
}

output "analytics_export_destination" {
  description = "Destination for storage analytics reports"
  value       = "${aws_s3_bucket.storage_optimization.id}/${var.analytics_reports_prefix}"
}

# =============================================================================
# Intelligent Tiering Information
# =============================================================================
output "intelligent_tiering_configuration_id" {
  description = "ID of the intelligent tiering configuration"
  value       = aws_s3_bucket_intelligent_tiering_configuration.storage_optimization.name
}

output "intelligent_tiering_status" {
  description = "Status of the intelligent tiering configuration"
  value       = aws_s3_bucket_intelligent_tiering_configuration.storage_optimization.status
}

output "intelligent_tiering_archive_days" {
  description = "Days after which objects move to Archive Access tier"
  value       = var.intelligent_tiering_archive_days
}

output "intelligent_tiering_deep_archive_days" {
  description = "Days after which objects move to Deep Archive Access tier"
  value       = var.intelligent_tiering_deep_archive_days
}

# =============================================================================
# Lifecycle Policy Information
# =============================================================================
output "lifecycle_policy_rules" {
  description = "Summary of lifecycle policy rules applied to the bucket"
  value = {
    frequently_accessed = {
      prefix = local.lifecycle_rules.frequently_accessed.prefix
      transitions = local.lifecycle_rules.frequently_accessed.transitions
    }
    infrequently_accessed = {
      prefix = local.lifecycle_rules.infrequently_accessed.prefix
      transitions = local.lifecycle_rules.infrequently_accessed.transitions
    }
    archive = {
      prefix = local.lifecycle_rules.archive.prefix
      transitions = local.lifecycle_rules.archive.transitions
    }
  }
}

output "lifecycle_cleanup_configuration" {
  description = "Configuration for incomplete multipart upload cleanup"
  value = {
    enabled = true
    days    = var.cleanup_incomplete_uploads_days
  }
}

# =============================================================================
# CloudWatch Dashboard Information
# =============================================================================
output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for storage monitoring"
  value       = aws_cloudwatch_dashboard.storage_optimization.dashboard_name
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.storage_optimization.dashboard_name}"
}

output "dashboard_metrics" {
  description = "List of metrics displayed in the CloudWatch dashboard"
  value = [
    "BucketSizeBytes by Storage Class",
    "NumberOfObjects",
    "Storage Distribution by Class"
  ]
}

# =============================================================================
# Budget Information
# =============================================================================
output "budget_name" {
  description = "Name of the AWS budget for cost monitoring"
  value       = aws_budgets_budget.s3_storage_cost.name
}

output "budget_limit" {
  description = "Monthly budget limit for S3 storage costs"
  value = {
    amount = var.budget_limit_amount
    unit   = "USD"
  }
}

output "budget_alert_threshold" {
  description = "Percentage threshold for budget alerts"
  value       = var.budget_alert_threshold
}

output "budget_alert_emails" {
  description = "Email addresses configured for budget alerts"
  value       = var.budget_alert_emails
  sensitive   = true
}

# =============================================================================
# Sample Data Information
# =============================================================================
output "sample_data_created" {
  description = "Whether sample data objects were created"
  value       = var.create_sample_data
}

output "sample_data_objects" {
  description = "List of sample data objects created (if enabled)"
  value = var.create_sample_data ? {
    frequently_accessed = [
      for obj in aws_s3_object.sample_frequently_accessed : obj.key
    ]
    infrequently_accessed = [
      for obj in aws_s3_object.sample_infrequently_accessed : obj.key
    ]
    archive = [
      for obj in aws_s3_object.sample_archive : obj.key
    ]
  } : {}
}

# =============================================================================
# Monitoring and Alerting Information
# =============================================================================
output "enhanced_notifications_enabled" {
  description = "Whether enhanced notifications via SNS are enabled"
  value       = var.enable_enhanced_notifications
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for budget alerts (if enabled)"
  value       = var.enable_enhanced_notifications ? aws_sns_topic.budget_alerts[0].arn : null
}

output "storage_alarms_enabled" {
  description = "Whether CloudWatch alarms for storage size are enabled"
  value       = var.enable_storage_alarms
}

output "storage_alarm_threshold" {
  description = "Storage size threshold for CloudWatch alarm (in bytes)"
  value       = var.enable_storage_alarms ? var.storage_size_alarm_threshold : null
}

# =============================================================================
# Cost Optimization Insights
# =============================================================================
output "cost_optimization_features" {
  description = "Summary of cost optimization features enabled"
  value = {
    storage_analytics     = true
    intelligent_tiering   = true
    lifecycle_policies    = true
    budget_monitoring     = true
    cleanup_policies      = true
    enhanced_notifications = var.enable_enhanced_notifications
    storage_alarms        = var.enable_storage_alarms
  }
}

output "potential_cost_savings" {
  description = "Potential cost savings from implemented optimizations"
  value = {
    standard_to_ia        = "40% reduction after transition"
    standard_to_glacier   = "68% reduction after transition"
    standard_to_deep_archive = "95% reduction after transition"
    intelligent_tiering   = "Automatic optimization based on access patterns"
    lifecycle_automation  = "Eliminates manual storage class management"
  }
}

# =============================================================================
# Operational Information
# =============================================================================
output "management_console_links" {
  description = "Direct links to AWS Management Console for resource management"
  value = {
    s3_bucket = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.storage_optimization.id}"
    cloudwatch_dashboard = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.storage_optimization.dashboard_name}"
    budget_console = "https://console.aws.amazon.com/billing/home#/budgets"
    cost_explorer = "https://console.aws.amazon.com/cost-reports/home"
  }
}

output "cli_commands" {
  description = "Useful AWS CLI commands for managing the created resources"
  value = {
    list_objects = "aws s3 ls s3://${aws_s3_bucket.storage_optimization.id} --recursive"
    get_storage_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name BucketSizeBytes --dimensions Name=BucketName,Value=${aws_s3_bucket.storage_optimization.id} Name=StorageType,Value=StandardStorage --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 86400 --statistics Average"
    view_lifecycle_config = "aws s3api get-bucket-lifecycle-configuration --bucket ${aws_s3_bucket.storage_optimization.id}"
    view_analytics_config = "aws s3api get-bucket-analytics-configuration --bucket ${aws_s3_bucket.storage_optimization.id} --id ${aws_s3_bucket_analytics_configuration.storage_analytics.name}"
  }
}

# =============================================================================
# Environment and Configuration Information
# =============================================================================
output "deployment_environment" {
  description = "Environment where the resources were deployed"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "terraform_workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

# =============================================================================
# Verification Commands
# =============================================================================
output "verification_commands" {
  description = "Commands to verify the deployment and configuration"
  value = {
    verify_bucket_exists = "aws s3 ls s3://${aws_s3_bucket.storage_optimization.id}"
    check_analytics_config = "aws s3api list-bucket-analytics-configurations --bucket ${aws_s3_bucket.storage_optimization.id}"
    check_intelligent_tiering = "aws s3api list-bucket-intelligent-tiering-configurations --bucket ${aws_s3_bucket.storage_optimization.id}"
    check_lifecycle_policy = "aws s3api get-bucket-lifecycle-configuration --bucket ${aws_s3_bucket.storage_optimization.id}"
    check_dashboard = "aws cloudwatch list-dashboards --dashboard-name-prefix 'S3-Storage-Cost-Optimization'"
    check_budget = "aws budgets describe-budget --account-id ${data.aws_caller_identity.current.account_id} --budget-name ${aws_budgets_budget.s3_storage_cost.name}"
  }
}

# =============================================================================
# Next Steps and Recommendations
# =============================================================================
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload sample data or migrate existing data to the bucket",
    "2. Monitor the CloudWatch dashboard for storage metrics",
    "3. Review storage analytics reports after 24-48 hours",
    "4. Adjust lifecycle policies based on your data access patterns",
    "5. Set up additional budget alerts if needed",
    "6. Consider enabling cross-region replication for disaster recovery",
    "7. Review and optimize costs monthly using the provided tools"
  ]
}

output "documentation_links" {
  description = "Useful documentation links for further learning"
  value = {
    s3_storage_classes = "https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html"
    s3_lifecycle_management = "https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html"
    s3_intelligent_tiering = "https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering.html"
    s3_storage_analytics = "https://docs.aws.amazon.com/AmazonS3/latest/userguide/analytics-storage-class.html"
    aws_budgets = "https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-managing-costs.html"
    cloudwatch_dashboards = "https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Dashboards.html"
  }
}