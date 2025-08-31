# S3 bucket outputs for cost estimate storage
output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing cost estimates"
  value       = aws_s3_bucket.cost_estimates.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing cost estimates"
  value       = aws_s3_bucket.cost_estimates.arn
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.cost_estimates.region
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.cost_estimates.bucket_domain_name
}

# Cost estimation project information
output "project_name" {
  description = "Name of the project for cost estimation tracking"
  value       = var.project_name
}

output "project_folder_path" {
  description = "S3 folder path for project-specific cost estimates"
  value       = "s3://${aws_s3_bucket.cost_estimates.id}/projects/${var.project_name}/"
}

# Budget and monitoring outputs
output "budget_name" {
  description = "Name of the AWS budget for cost monitoring"
  value       = aws_budgets_budget.project_budget.name
}

output "budget_amount" {
  description = "Monthly budget amount in USD"
  value       = "${aws_budgets_budget.project_budget.limit_amount} ${aws_budgets_budget.project_budget.limit_unit}"
}

output "budget_alert_threshold" {
  description = "Budget alert threshold percentage"
  value       = "${var.budget_alert_threshold}%"
}

# SNS topic outputs (conditional)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for budget notifications"
  value       = var.notification_email != "" ? aws_sns_topic.budget_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for budget notifications"
  value       = var.notification_email != "" ? aws_sns_topic.budget_alerts[0].name : null
}

# Sample files information
output "sample_estimate_file" {
  description = "S3 key of the sample cost estimate file"
  value       = aws_s3_object.sample_estimate.key
}

output "sample_summary_file" {
  description = "S3 key of the sample estimate summary file"
  value       = aws_s3_object.sample_summary.key
}

# Folder structure information
output "estimate_folders" {
  description = "List of all created folders in the S3 bucket"
  value       = local.all_folders
}

# Storage configuration outputs
output "versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.enable_versioning
}

output "lifecycle_policy_enabled" {
  description = "Whether S3 lifecycle policy is enabled for cost optimization"
  value       = var.enable_lifecycle_policy
}

output "encryption_enabled" {
  description = "Server-side encryption configuration for the S3 bucket"
  value       = "AES256"
}

# CloudWatch logs output
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for cost estimation activities"
  value       = aws_cloudwatch_log_group.cost_estimation_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for cost estimation activities"
  value       = aws_cloudwatch_log_group.cost_estimation_logs.arn
}

# AWS Pricing Calculator information
output "pricing_calculator_url" {
  description = "URL to AWS Pricing Calculator for creating new estimates"
  value       = "https://calculator.aws/#/"
}

# Usage instructions
output "usage_instructions" {
  description = "Instructions for using the cost estimation infrastructure"
  value = <<-EOT
## Cost Estimation Infrastructure Usage

1. **Access AWS Pricing Calculator**: Visit ${aws_s3_bucket.cost_estimates.bucket_domain_name}
2. **Create Cost Estimates**: Use the calculator to model your AWS resources
3. **Upload Estimates**: Store your estimates in S3 at s3://${aws_s3_bucket.cost_estimates.id}/projects/${var.project_name}/
4. **Monitor Costs**: Budget alerts are configured at ${var.budget_alert_threshold}% of $${var.monthly_budget_amount}/month
5. **View Historical Data**: Access previous estimates in organized folders within the S3 bucket

## Folder Structure:
${join("\n", formatlist("- %s", local.all_folders))}

## Cost Optimization:
- Files automatically transition to cheaper storage classes over time
- Versioning enabled for estimate history tracking
- Lifecycle policies manage storage costs automatically
EOT
}

# Resource tags information
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Account and region information
output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# Terraform state information
output "terraform_workspace" {
  description = "Terraform workspace used for this deployment"
  value       = terraform.workspace
}

output "deployment_timestamp" {
  description = "Timestamp of the Terraform deployment"
  value       = timestamp()
}