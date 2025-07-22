# Outputs for Infrastructure Policy Validation with CloudFormation Guard
# These outputs provide important information for integration and validation

# S3 Bucket Information
output "guard_policies_bucket_name" {
  description = "Name of the S3 bucket containing Guard rules and templates"
  value       = aws_s3_bucket.guard_policies.bucket
}

output "guard_policies_bucket_arn" {
  description = "ARN of the S3 bucket containing Guard rules and templates"
  value       = aws_s3_bucket.guard_policies.arn
}

output "guard_policies_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.guard_policies.bucket_domain_name
}

output "guard_policies_bucket_region" {
  description = "Region where the S3 bucket is hosted"
  value       = aws_s3_bucket.guard_policies.region
}

# IAM Role Information
output "guard_validation_role_name" {
  description = "Name of the IAM role for Guard validation automation"
  value       = aws_iam_role.guard_validation_role.name
}

output "guard_validation_role_arn" {
  description = "ARN of the IAM role for Guard validation automation"
  value       = aws_iam_role.guard_validation_role.arn
}

output "guard_validation_role_path" {
  description = "Path of the IAM role for organizational hierarchy"
  value       = aws_iam_role.guard_validation_role.path
}

# CloudWatch Information
output "guard_validation_log_group_name" {
  description = "Name of the CloudWatch Log Group for validation logs"
  value       = aws_cloudwatch_log_group.guard_validation_logs.name
}

output "guard_validation_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for validation logs"
  value       = aws_cloudwatch_log_group.guard_validation_logs.arn
}

output "guard_validation_log_group_retention" {
  description = "Retention period in days for validation logs"
  value       = aws_cloudwatch_log_group.guard_validation_logs.retention_in_days
}

# SNS Topic Information
output "guard_validation_notifications_topic_arn" {
  description = "ARN of the SNS topic for validation notifications"
  value       = aws_sns_topic.guard_validation_notifications.arn
}

output "guard_validation_notifications_topic_name" {
  description = "Name of the SNS topic for validation notifications"
  value       = aws_sns_topic.guard_validation_notifications.name
}

# CloudWatch Dashboard Information
output "guard_validation_dashboard_url" {
  description = "URL to access the CloudWatch dashboard for policy validation metrics"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.guard_validation_dashboard.dashboard_name}"
}

output "guard_validation_dashboard_name" {
  description = "Name of the CloudWatch dashboard for monitoring"
  value       = aws_cloudwatch_dashboard.guard_validation_dashboard.dashboard_name
}

# Guard Rules Repository Structure
output "guard_rules_s3_paths" {
  description = "S3 paths for different categories of Guard rules"
  value = {
    security_rules = {
      s3_security  = "s3://${aws_s3_bucket.guard_policies.bucket}/guard-rules/security/s3-security.guard"
      iam_security = "s3://${aws_s3_bucket.guard_policies.bucket}/guard-rules/security/iam-security.guard"
    }
    compliance_rules = {
      resource_compliance = "s3://${aws_s3_bucket.guard_policies.bucket}/guard-rules/compliance/resource-compliance.guard"
    }
    cost_optimization_rules = {
      cost_controls = "s3://${aws_s3_bucket.guard_policies.bucket}/guard-rules/cost-optimization/cost-controls.guard"
    }
    manifest = "s3://${aws_s3_bucket.guard_policies.bucket}/rules-manifest.json"
  }
}

# Test Templates Information
output "test_templates_s3_paths" {
  description = "S3 paths for example CloudFormation templates"
  value = {
    compliant_template     = "s3://${aws_s3_bucket.guard_policies.bucket}/templates/compliant-template.yaml"
    non_compliant_template = "s3://${aws_s3_bucket.guard_policies.bucket}/templates/non-compliant-template.yaml"
  }
}

# CLI Commands for Local Validation
output "local_validation_commands" {
  description = "CLI commands to download rules for local validation"
  value = {
    download_rules = "aws s3 cp s3://${aws_s3_bucket.guard_policies.bucket}/guard-rules/ ./local-rules/ --recursive"
    download_templates = "aws s3 cp s3://${aws_s3_bucket.guard_policies.bucket}/templates/ ./test-templates/ --recursive"
    validate_template = "cfn-guard validate --data <template-file> --rules <rule-file>"
  }
}

# CI/CD Integration Information
output "cicd_integration_commands" {
  description = "Commands and information for CI/CD pipeline integration"
  value = {
    validation_role_arn = aws_iam_role.guard_validation_role.arn
    bucket_name = aws_s3_bucket.guard_policies.bucket
    log_group_name = aws_cloudwatch_log_group.guard_validation_logs.name
    example_validation_command = "cfn-guard validate --data template.yaml --rules s3://${aws_s3_bucket.guard_policies.bucket}/guard-rules/security/s3-security.guard"
  }
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where the infrastructure is deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where the infrastructure is deployed"
  value       = data.aws_region.current.name
}

# Random Suffix for Resource Names
output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed Guard validation configuration"
  value = {
    environment = var.environment
    team = var.team
    cost_center = var.cost_center
    log_retention_days = var.log_retention_days
    bucket_versioning_enabled = var.bucket_versioning_enabled
    bucket_lifecycle_enabled = var.bucket_lifecycle_enabled
    dashboard_enabled = var.enable_dashboard
    sns_notifications_enabled = var.enable_sns_notifications
  }
}

# S3 Bucket Policy Information
output "s3_bucket_security_features" {
  description = "Security features enabled on the S3 bucket"
  value = {
    versioning_enabled = aws_s3_bucket_versioning.guard_policies_versioning.versioning_configuration[0].status
    encryption_enabled = true
    public_access_blocked = true
    lifecycle_policies_enabled = var.bucket_lifecycle_enabled
  }
}

# Validation Scripts and Tools
output "validation_tools_info" {
  description = "Information about validation tools and scripts"
  value = {
    cloudformation_guard_cli = "https://docs.aws.amazon.com/cfn-guard/latest/ug/setting-up-guard.html"
    rule_writing_guide = "https://docs.aws.amazon.com/cfn-guard/latest/ug/writing-rules.html"
    aws_config_integration = "https://docs.aws.amazon.com/cfn-guard/latest/ug/aws-config-integration.html"
    github_repository = "https://github.com/aws-cloudformation/cloudformation-guard"
  }
}

# Cost Optimization Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the Guard validation infrastructure"
  value = {
    s3_storage = "~$0.50 (for ~10GB of rules and reports)"
    cloudwatch_logs = "~$2.00 (for log ingestion and storage)"
    cloudwatch_dashboard = "~$3.00 (for dashboard usage)"
    sns_notifications = "~$0.50 (for notification delivery)"
    total_estimated = "~$6.00 per month"
    note = "Costs may vary based on usage patterns and AWS pricing changes"
  }
}

# Compliance and Governance Information
output "compliance_features" {
  description = "Compliance and governance features provided by this solution"
  value = {
    policy_as_code = "Guard rules stored as version-controlled code"
    audit_trail = "S3 versioning and CloudWatch logs provide audit trails"
    centralized_governance = "Centralized rule repository for organization-wide policies"
    automated_validation = "Automated validation in CI/CD pipelines"
    reporting = "Detailed validation reports stored in S3"
    monitoring = "CloudWatch dashboard for validation metrics"
  }
}