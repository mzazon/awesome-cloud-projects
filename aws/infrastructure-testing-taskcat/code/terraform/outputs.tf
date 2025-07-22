# Outputs for TaskCat CloudFormation testing infrastructure
# These outputs provide essential information for using the TaskCat testing environment

output "s3_bucket_name" {
  description = "Name of the S3 bucket for TaskCat artifacts and templates"
  value       = aws_s3_bucket.taskcat_artifacts.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for TaskCat artifacts"
  value       = aws_s3_bucket.taskcat_artifacts.arn
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.taskcat_artifacts.region
}

output "taskcat_execution_role_arn" {
  description = "ARN of the IAM role for TaskCat execution"
  value       = aws_iam_role.taskcat_execution_role.arn
}

output "taskcat_execution_role_name" {
  description = "Name of the IAM role for TaskCat execution"
  value       = aws_iam_role.taskcat_execution_role.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for TaskCat logs"
  value       = aws_cloudwatch_log_group.taskcat_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for TaskCat logs"
  value       = aws_cloudwatch_log_group.taskcat_logs.arn
}

output "key_pair_name" {
  description = "Name of the EC2 key pair for TaskCat testing"
  value       = var.key_pair_name != "" ? var.key_pair_name : (length(aws_key_pair.taskcat_key_pair) > 0 ? aws_key_pair.taskcat_key_pair[0].key_name : "")
}

output "private_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the private key (if generated)"
  value       = length(aws_secretsmanager_secret.taskcat_private_key) > 0 ? aws_secretsmanager_secret.taskcat_private_key[0].arn : ""
}

output "lambda_function_name" {
  description = "Name of the Lambda function for TaskCat automation"
  value       = aws_lambda_function.taskcat_automation.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for TaskCat automation"
  value       = aws_lambda_function.taskcat_automation.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for TaskCat notifications (if enabled)"
  value       = length(aws_sns_topic.taskcat_notifications) > 0 ? aws_sns_topic.taskcat_notifications[0].arn : ""
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail for TaskCat operations (if enabled)"
  value       = length(aws_cloudtrail.taskcat_trail) > 0 ? aws_cloudtrail.taskcat_trail[0].name : ""
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for TaskCat operations (if enabled)"
  value       = length(aws_cloudtrail.taskcat_trail) > 0 ? aws_cloudtrail.taskcat_trail[0].arn : ""
}

output "project_name" {
  description = "Name of the TaskCat project"
  value       = var.project_name
}

output "environment_name" {
  description = "Environment name for the TaskCat testing infrastructure"
  value       = var.environment_name
}

output "aws_regions" {
  description = "List of AWS regions configured for TaskCat testing"
  value       = var.aws_regions
}

output "vpc_cidr_blocks" {
  description = "CIDR blocks configured for test VPCs"
  value       = var.vpc_cidr_blocks
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

output "current_aws_account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "current_aws_region" {
  description = "Current AWS region"
  value       = data.aws_region.current.name
}

output "taskcat_config_s3_key" {
  description = "S3 key for the TaskCat configuration file"
  value       = aws_s3_object.taskcat_config.key
}

output "cloudwatch_event_rule_name" {
  description = "Name of the CloudWatch Event Rule for scheduled TaskCat execution"
  value       = aws_cloudwatch_event_rule.taskcat_schedule.name
}

# Deployment instructions output
output "deployment_instructions" {
  description = "Instructions for using the TaskCat testing infrastructure"
  value = <<-EOT
    TaskCat Infrastructure Deployment Complete!
    
    ## Next Steps:
    
    1. **Install TaskCat:**
       pip install taskcat
    
    2. **Configure AWS CLI:**
       aws configure
    
    3. **Download TaskCat config:**
       aws s3 cp s3://${aws_s3_bucket.taskcat_artifacts.bucket}/config/.taskcat.yml ./.taskcat.yml
    
    4. **Upload your CloudFormation templates:**
       aws s3 sync ./templates/ s3://${aws_s3_bucket.taskcat_artifacts.bucket}/templates/
    
    5. **Run TaskCat tests:**
       taskcat test run --output-directory ./taskcat_outputs
    
    ## Key Resources:
    - S3 Bucket: ${aws_s3_bucket.taskcat_artifacts.bucket}
    - IAM Role: ${aws_iam_role.taskcat_execution_role.name}
    - Log Group: ${aws_cloudwatch_log_group.taskcat_logs.name}
    - Key Pair: ${var.key_pair_name != "" ? var.key_pair_name : (length(aws_key_pair.taskcat_key_pair) > 0 ? aws_key_pair.taskcat_key_pair[0].key_name : "")}
    
    ## Test Regions: ${join(", ", var.aws_regions)}
    
    For detailed usage instructions, refer to the README.md file.
  EOT
}

# Security and compliance information
output "security_notes" {
  description = "Important security considerations for the TaskCat infrastructure"
  value = <<-EOT
    Security Configuration Summary:
    
    ## S3 Bucket Security:
    - Server-side encryption enabled (AES256)
    - Public access blocked
    - Versioning enabled: ${var.s3_bucket_versioning_enabled}
    - Lifecycle policy configured for cost optimization
    
    ## IAM Security:
    - Least privilege access principles applied
    - Role-based access for TaskCat execution
    - Separate roles for Lambda automation
    - Cross-service access properly configured
    
    ## Monitoring:
    - CloudWatch logging enabled
    - CloudTrail logging: ${var.enable_cloudtrail_logging ? "enabled" : "disabled"}
    - SNS notifications: ${var.notification_email != "" ? "enabled" : "disabled"}
    
    ## Best Practices:
    - Force destroy on S3 bucket: ${var.s3_bucket_force_destroy} (disable for production)
    - Test timeout: ${var.test_timeout_minutes} minutes
    - Log retention: ${var.cloudtrail_retention_days} days
    
    Please review and adjust security settings based on your organization's requirements.
  EOT
}