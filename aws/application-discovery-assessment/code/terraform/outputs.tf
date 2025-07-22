# Outputs for Application Discovery Service Infrastructure
# This file defines the outputs that will be displayed after deployment

# S3 Bucket Information
output "discovery_bucket_name" {
  description = "Name of the S3 bucket storing discovery data"
  value       = aws_s3_bucket.discovery_data.bucket
}

output "discovery_bucket_arn" {
  description = "ARN of the S3 bucket storing discovery data"
  value       = aws_s3_bucket.discovery_data.arn
}

output "discovery_bucket_region" {
  description = "Region where the S3 bucket is located"
  value       = aws_s3_bucket.discovery_data.region
}

# KMS Key Information
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.discovery_key[0].id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.discovery_key[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_alias.discovery_key_alias[0].name : null
}

# IAM Role Information
output "discovery_service_role_name" {
  description = "Name of the IAM role used by Application Discovery Service"
  value       = aws_iam_role.discovery_service_role.name
}

output "discovery_service_role_arn" {
  description = "ARN of the IAM role used by Application Discovery Service"
  value       = aws_iam_role.discovery_service_role.arn
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function for automated discovery reports"
  value       = var.enable_automated_reports ? aws_lambda_function.discovery_automation[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for automated discovery reports"
  value       = var.enable_automated_reports ? aws_lambda_function.discovery_automation[0].arn : null
}

# CloudWatch Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = var.enable_automated_reports ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "cloudwatch_event_rule_name" {
  description = "Name of the CloudWatch Events rule for automated reports"
  value       = var.enable_automated_reports ? aws_cloudwatch_event_rule.discovery_schedule[0].name : null
}

# SNS Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.discovery_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.discovery_notifications[0].name : null
}

# Athena Information
output "athena_database_name" {
  description = "Name of the Athena database for discovery analysis"
  value       = var.enable_athena_analysis ? aws_athena_database.discovery_database[0].name : null
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for discovery queries"
  value       = var.enable_athena_analysis ? aws_athena_workgroup.discovery_workgroup[0].name : null
}

# Migration Hub Information
output "migration_hub_home_region" {
  description = "AWS region configured as Migration Hub home region"
  value       = var.migration_hub_home_region
}

# Application Groups Information
output "application_groups" {
  description = "List of application groups created for discovery"
  value = [
    for group in var.application_groups : {
      name        = "${group.name}-${random_string.suffix.result}"
      description = group.description
    }
  ]
}

# General Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = local.account_id
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = random_string.suffix.result
}

# Configuration Information
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    environment               = var.environment
    continuous_export_enabled = var.enable_continuous_export
    automated_reports_enabled = var.enable_automated_reports
    sns_notifications_enabled = var.enable_sns_notifications
    athena_analysis_enabled   = var.enable_athena_analysis
    encryption_enabled        = var.enable_encryption
    bucket_versioning_enabled = var.enable_bucket_versioning
    bucket_lifecycle_days     = var.bucket_lifecycle_days
    report_schedule          = var.report_schedule
  }
}

# Next Steps Information
output "next_steps" {
  description = "Instructions for next steps after deployment"
  value = <<-EOT
    1. Deploy the Agentless Collector OVA to your VMware environment:
       - Navigate to AWS Migration Hub Console > Discover > Tools
       - Download the AWS Application Discovery Service Agentless Collector
       - Deploy the OVA file to your vCenter environment
    
    2. Install Discovery Agents on physical servers:
       - Download agents from the Migration Hub console
       - Install on Linux: sudo ./install -r ${var.aws_region} -k <ACCESS_KEY> -s <SECRET_KEY>
       - Start data collection: sudo /opt/aws/discovery/bin/aws-discovery-daemon --start
    
    3. Start data collection:
       - aws discovery start-data-collection-by-agent-ids --agent-ids <AGENT_IDS> --region ${var.aws_region}
    
    4. Monitor discovery progress:
       - Check S3 bucket: ${aws_s3_bucket.discovery_data.bucket}
       - Use Migration Hub console for visualization
       - Query data using Athena in workgroup: ${var.enable_athena_analysis ? aws_athena_workgroup.discovery_workgroup[0].name : "N/A"}
    
    5. Configure continuous export (if not already enabled):
       - aws discovery start-continuous-export --s3-bucket ${aws_s3_bucket.discovery_data.bucket} --region ${var.aws_region}
  EOT
}

# Resource URLs for Console Access
output "console_urls" {
  description = "AWS Console URLs for accessing deployed resources"
  value = {
    migration_hub        = "https://${var.migration_hub_home_region}.console.aws.amazon.com/migrationhub/home?region=${var.migration_hub_home_region}"
    discovery_service    = "https://${var.aws_region}.console.aws.amazon.com/discovery/home?region=${var.aws_region}"
    s3_bucket           = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.discovery_data.bucket}?region=${var.aws_region}"
    athena_workgroup    = var.enable_athena_analysis ? "https://${var.aws_region}.console.aws.amazon.com/athena/home?region=${var.aws_region}#/workgroup/details/${aws_athena_workgroup.discovery_workgroup[0].name}" : null
    lambda_function     = var.enable_automated_reports ? "https://${var.aws_region}.console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${aws_lambda_function.discovery_automation[0].function_name}" : null
    cloudwatch_logs     = var.enable_automated_reports ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs[0].name, "/", "%2F")}" : null
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    note = "Costs vary based on data volume and usage patterns"
    estimated_monthly_cost = {
      s3_storage_gb        = "~$0.023 per GB stored"
      athena_queries       = "~$5.00 per TB scanned"
      lambda_invocations   = "~$0.20 per 1M requests"
      kms_key_usage        = "~$1.00 per month"
      cloudwatch_logs      = "~$0.50 per GB ingested"
      data_transfer        = "First 1GB free, then $0.09 per GB"
    }
    discovery_service_cost = "No additional charges for discovery data collection"
  }
}