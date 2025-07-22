# S3 Bucket Information
output "bucket_name" {
  description = "Name of the created S3 bucket for long-term archiving"
  value       = aws_s3_bucket.archive_bucket.id
}

output "bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.archive_bucket.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.archive_bucket.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.archive_bucket.bucket_regional_domain_name
}

# Bucket Configuration Details
output "bucket_region" {
  description = "AWS region where the bucket is created"
  value       = aws_s3_bucket.archive_bucket.region
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket"
  value       = var.enable_versioning
}

output "encryption_enabled" {
  description = "Whether server-side encryption is enabled"
  value       = var.enable_server_side_encryption
}

output "encryption_algorithm" {
  description = "Server-side encryption algorithm used"
  value       = var.enable_server_side_encryption ? var.sse_algorithm : "None"
}

# Lifecycle Policy Configuration
output "archives_transition_days" {
  description = "Number of days before files in archives/ folder transition to Deep Archive"
  value       = var.archives_transition_days
}

output "general_transition_days" {
  description = "Number of days before general files transition to Deep Archive"
  value       = var.general_transition_days
}

# SNS Notification Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for archive notifications"
  value       = var.enable_notifications ? aws_sns_topic.archive_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for archive notifications"
  value       = var.enable_notifications ? aws_sns_topic.archive_notifications[0].name : null
}

output "notification_email_subscribed" {
  description = "Whether an email subscription was created for notifications"
  value       = var.enable_notifications && var.notification_email != ""
}

# Inventory Configuration
output "inventory_enabled" {
  description = "Whether S3 inventory is enabled for archive tracking"
  value       = var.enable_inventory
}

output "inventory_frequency" {
  description = "Frequency of inventory reports"
  value       = var.enable_inventory ? var.inventory_frequency : null
}

output "inventory_destination_prefix" {
  description = "S3 prefix where inventory reports are stored"
  value       = var.enable_inventory ? "inventory-reports/" : null
}

# Security Configuration
output "public_access_blocked" {
  description = "Whether public access is blocked on the bucket"
  value       = var.enable_public_access_block
}

# Sample Upload Paths
output "sample_upload_commands" {
  description = "Sample AWS CLI commands to upload files to different archiving paths"
  value = {
    fast_archive = "aws s3 cp your-file.pdf s3://${aws_s3_bucket.archive_bucket.id}/archives/ (transitions in ${var.archives_transition_days} days)"
    standard_archive = "aws s3 cp your-file.pdf s3://${aws_s3_bucket.archive_bucket.id}/general/ (transitions in ${var.general_transition_days} days)"
  }
}

# Cost Optimization Information
output "estimated_deep_archive_cost_per_tb_monthly" {
  description = "Estimated monthly cost per TB in Glacier Deep Archive (approximate)"
  value       = "$1.00 USD (varies by region)"
}

output "retrieval_information" {
  description = "Information about data retrieval from Deep Archive"
  value = {
    standard_retrieval = "9-12 hours retrieval time"
    bulk_retrieval     = "Up to 48 hours retrieval time (lowest cost)"
    retrieval_command  = "aws s3api restore-object --bucket ${aws_s3_bucket.archive_bucket.id} --key <object-key> --restore-request 'Days=5,GlacierJobParameters={Tier=Bulk}'"
  }
}

# Monitoring and Management
output "lifecycle_policy_rules" {
  description = "Summary of configured lifecycle policy rules"
  value = {
    archives_rule = "Files in archives/ folder transition to Deep Archive after ${var.archives_transition_days} days"
    general_rule  = "All other files transition to Deep Archive after ${var.general_transition_days} days"
    versioning_rule = var.enable_versioning ? "Non-current versions transition after ${var.general_transition_days + 30} days" : "Versioning disabled"
  }
}

# Operational Commands
output "useful_cli_commands" {
  description = "Useful AWS CLI commands for managing the archive"
  value = {
    list_objects = "aws s3 ls s3://${aws_s3_bucket.archive_bucket.id}/ --recursive"
    check_storage_class = "aws s3api head-object --bucket ${aws_s3_bucket.archive_bucket.id} --key <object-key>"
    download_inventory = "aws s3 sync s3://${aws_s3_bucket.archive_bucket.id}/inventory-reports/ ./inventory-reports/"
    monitor_lifecycle = "aws s3api get-bucket-lifecycle-configuration --bucket ${aws_s3_bucket.archive_bucket.id}"
  }
}

# Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# Resource Tags Applied
output "resource_tags" {
  description = "Tags applied to all resources"
  value = merge(
    {
      Project     = "Long-term Data Archiving"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "long-term-data-archiving-s3-glacier"
    },
    var.additional_tags
  )
}