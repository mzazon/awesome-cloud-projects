# Outputs for AWS CLI Setup and First Commands Terraform Infrastructure
# These outputs provide essential information for using the created infrastructure

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket created for CLI tutorial"
  value       = aws_s3_bucket.cli_tutorial_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket created for CLI tutorial"
  value       = aws_s3_bucket.cli_tutorial_bucket.arn
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket was created"
  value       = aws_s3_bucket.cli_tutorial_bucket.region
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.cli_tutorial_bucket.bucket_domain_name
}

output "s3_bucket_hosted_zone_id" {
  description = "Route 53 hosted zone ID for the S3 bucket"
  value       = aws_s3_bucket.cli_tutorial_bucket.hosted_zone_id
}

# IAM Policy Information
output "s3_access_policy_arn" {
  description = "ARN of the IAM policy for S3 access"
  value       = aws_iam_policy.cli_tutorial_s3_policy.arn
}

output "s3_access_policy_name" {
  description = "Name of the IAM policy for S3 access"
  value       = aws_iam_policy.cli_tutorial_s3_policy.name
}

# IAM Role Information (if created)
output "ec2_role_arn" {
  description = "ARN of the IAM role for EC2 instances (if created)"
  value       = var.create_ec2_role ? aws_iam_role.cli_tutorial_ec2_role[0].arn : null
}

output "ec2_role_name" {
  description = "Name of the IAM role for EC2 instances (if created)"
  value       = var.create_ec2_role ? aws_iam_role.cli_tutorial_ec2_role[0].name : null
}

output "ec2_instance_profile_arn" {
  description = "ARN of the instance profile for EC2 (if created)"
  value       = var.create_ec2_role ? aws_iam_instance_profile.cli_tutorial_ec2_profile[0].arn : null
}

output "ec2_instance_profile_name" {
  description = "Name of the instance profile for EC2 (if created)"
  value       = var.create_ec2_role ? aws_iam_instance_profile.cli_tutorial_ec2_profile[0].name : null
}

# CloudWatch Log Group Information (if created)
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group (if created)"
  value       = var.enable_cloudwatch_logging ? aws_cloudwatch_log_group.cli_tutorial_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group (if created)"
  value       = var.enable_cloudwatch_logging ? aws_cloudwatch_log_group.cli_tutorial_logs[0].arn : null
}

# Sample Objects Information (if created)
output "sample_objects" {
  description = "List of sample objects created in the S3 bucket"
  value = var.create_sample_objects ? {
    welcome_file = aws_s3_object.sample_file[0].key
    config_file  = aws_s3_object.sample_json_file[0].key
    logs_dir     = aws_s3_object.logs_directory[0].key
  } : {}
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

# CLI Commands for Quick Reference
output "cli_commands" {
  description = "Sample AWS CLI commands to practice with the created infrastructure"
  value = {
    list_bucket_contents    = "aws s3 ls s3://${aws_s3_bucket.cli_tutorial_bucket.id}/"
    list_all_buckets       = "aws s3 ls"
    get_bucket_location    = "aws s3api get-bucket-location --bucket ${aws_s3_bucket.cli_tutorial_bucket.id}"
    get_bucket_encryption  = "aws s3api get-bucket-encryption --bucket ${aws_s3_bucket.cli_tutorial_bucket.id}"
    upload_file            = "aws s3 cp <local-file> s3://${aws_s3_bucket.cli_tutorial_bucket.id}/"
    download_file          = "aws s3 cp s3://${aws_s3_bucket.cli_tutorial_bucket.id}/<file-key> <local-path>"
    sync_directory         = "aws s3 sync <local-directory> s3://${aws_s3_bucket.cli_tutorial_bucket.id}/<prefix>/"
    get_caller_identity    = "aws sts get-caller-identity"
    list_objects_detailed  = "aws s3api list-objects-v2 --bucket ${aws_s3_bucket.cli_tutorial_bucket.id}"
    head_bucket           = "aws s3api head-bucket --bucket ${aws_s3_bucket.cli_tutorial_bucket.id}"
  }
}

# Configuration Information
output "configuration_summary" {
  description = "Summary of the infrastructure configuration"
  value = {
    bucket_name                = aws_s3_bucket.cli_tutorial_bucket.id
    versioning_enabled         = var.enable_s3_versioning
    encryption_enabled         = var.enable_bucket_encryption
    encryption_algorithm       = var.encryption_algorithm
    public_access_blocked      = var.enable_public_access_block
    lifecycle_cleanup_days     = var.bucket_lifecycle_days
    sample_objects_created     = var.create_sample_objects
    ec2_role_created          = var.create_ec2_role
    cloudwatch_logging_enabled = var.enable_cloudwatch_logging
    environment               = var.environment
  }
}

# Resource Tags Applied
output "resource_tags" {
  description = "Common tags applied to resources"
  value = merge({
    Name        = "AWS CLI Tutorial Infrastructure"
    Purpose     = "AWS CLI Learning and Practice"
    Environment = var.environment
    Recipe      = "aws-cli-setup-first-commands"
    ManagedBy   = "Terraform"
  }, var.tags)
}

# Security Information
output "security_features" {
  description = "Security features enabled for the tutorial infrastructure"
  value = {
    s3_bucket_encryption          = var.enable_bucket_encryption ? "Enabled (${var.encryption_algorithm})" : "Disabled"
    s3_public_access_block        = var.enable_public_access_block ? "Enabled" : "Disabled"
    s3_versioning                 = var.enable_s3_versioning ? "Enabled" : "Disabled"
    iam_policy_least_privilege    = "Enabled - Policy grants minimal S3 permissions"
    lifecycle_cleanup             = "Enabled - Objects deleted after ${var.bucket_lifecycle_days} days"
    resource_tagging              = "Enabled - All resources tagged for identification"
  }
}

# Learning Resources
output "learning_resources" {
  description = "Helpful links and commands for AWS CLI learning"
  value = {
    aws_cli_user_guide      = "https://docs.aws.amazon.com/cli/latest/userguide/"
    s3_cli_reference        = "https://docs.aws.amazon.com/cli/latest/reference/s3/"
    s3api_cli_reference     = "https://docs.aws.amazon.com/cli/latest/reference/s3api/"
    aws_configuration_guide = "https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html"
    jmespath_tutorial      = "https://jmespath.org/tutorial.html"
    help_command           = "aws s3 help"
    help_subcommand        = "aws s3 cp help"
  }
}

# Cost Optimization Information
output "cost_optimization" {
  description = "Information about cost optimization features"
  value = {
    lifecycle_policy           = "Enabled - Objects deleted after ${var.bucket_lifecycle_days} days to minimize storage costs"
    versioning_cleanup         = "Enabled - Non-current versions deleted after 1 day"
    multipart_upload_cleanup   = "Enabled - Incomplete uploads cleaned up after 1 day"
    estimated_monthly_cost     = "Minimal - S3 storage and request charges only, typically < $1/month for tutorial use"
    cost_monitoring_tip        = "Use 'aws ce get-cost-and-usage' CLI command to monitor actual costs"
  }
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Common troubleshooting commands and tips"
  value = {
    check_credentials        = "aws sts get-caller-identity"
    check_region            = "aws configure get region"
    list_profiles           = "aws configure list-profiles"
    check_permissions       = "aws iam simulate-principal-policy --policy-source-arn <your-arn> --action-names s3:ListBucket --resource-arns ${aws_s3_bucket.cli_tutorial_bucket.arn}"
    bucket_exists_check     = "aws s3api head-bucket --bucket ${aws_s3_bucket.cli_tutorial_bucket.id}"
    debug_mode              = "aws s3 ls --debug"
    common_error_solution   = "Ensure AWS credentials are configured and you have proper permissions"
  }
}