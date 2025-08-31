# Amazon Q Developer Terraform Outputs
# These outputs provide information about the created resources

# Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where Amazon Q Developer resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where Amazon Q Developer resources are deployed"
  value       = data.aws_region.current.name
}

output "resource_prefix" {
  description = "Prefix used for all Amazon Q Developer resources"
  value       = var.resource_prefix
}

# IAM Role Outputs
output "admin_role_arn" {
  description = "ARN of the Amazon Q Developer administrative role"
  value       = var.create_admin_role ? aws_iam_role.amazon_q_admin_role[0].arn : null
}

output "admin_role_name" {
  description = "Name of the Amazon Q Developer administrative role"
  value       = var.create_admin_role ? aws_iam_role.amazon_q_admin_role[0].name : null
}

output "user_role_arn" {
  description = "ARN of the Amazon Q Developer user role"
  value       = var.create_user_role ? aws_iam_role.amazon_q_user_role[0].arn : null
}

output "user_role_name" {
  description = "Name of the Amazon Q Developer user role"
  value       = var.create_user_role ? aws_iam_role.amazon_q_user_role[0].name : null
}

# IAM Policy Outputs
output "admin_policy_arn" {
  description = "ARN of the Amazon Q Developer administrative policy"
  value       = var.create_admin_role ? aws_iam_policy.amazon_q_admin_policy[0].arn : null
}

output "user_policy_arn" {
  description = "ARN of the Amazon Q Developer user policy"
  value       = var.create_user_role ? aws_iam_policy.amazon_q_user_policy[0].arn : null
}

# IAM Identity Center Outputs
output "identity_center_permission_set_arn" {
  description = "ARN of the IAM Identity Center permission set for Amazon Q Developer"
  value       = var.enable_identity_center ? aws_ssoadmin_permission_set.amazon_q_permission_set[0].arn : null
}

output "identity_center_permission_set_name" {
  description = "Name of the IAM Identity Center permission set for Amazon Q Developer"
  value       = var.enable_identity_center ? aws_ssoadmin_permission_set.amazon_q_permission_set[0].name : null
}

output "identity_center_instance_arn" {
  description = "ARN of the IAM Identity Center instance used for Amazon Q Developer"
  value       = var.enable_identity_center ? var.identity_center_instance_arn : null
}

# Monitoring and Logging Outputs
output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Amazon Q Developer usage monitoring"
  value       = var.enable_usage_monitoring ? aws_cloudwatch_log_group.amazon_q_usage_logs[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Amazon Q Developer usage monitoring"
  value       = var.enable_usage_monitoring ? aws_cloudwatch_log_group.amazon_q_usage_logs[0].name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for Amazon Q Developer metrics"
  value = var.enable_usage_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.amazon_q_dashboard[0].dashboard_name}" : null
}

# S3 Bucket Outputs
output "config_bucket_name" {
  description = "Name of the S3 bucket for Amazon Q Developer configuration and logs"
  value       = var.create_config_bucket ? aws_s3_bucket.amazon_q_config_bucket[0].bucket : null
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket for Amazon Q Developer configuration and logs"
  value       = var.create_config_bucket ? aws_s3_bucket.amazon_q_config_bucket[0].arn : null
}

output "config_bucket_domain_name" {
  description = "Domain name of the S3 bucket for Amazon Q Developer configuration"
  value       = var.create_config_bucket ? aws_s3_bucket.amazon_q_config_bucket[0].bucket_domain_name : null
}

# Setup and Configuration Outputs
output "vs_code_extension_command" {
  description = "Command to install Amazon Q Developer extension in VS Code"
  value       = "code --install-extension AmazonWebServices.amazon-q-vscode"
}

output "setup_instructions_file" {
  description = "Path to the generated setup instructions file"
  value       = local_file.setup_instructions.filename
}

# Authentication Configuration Outputs
output "authentication_methods" {
  description = "Available authentication methods for Amazon Q Developer"
  value = {
    aws_builder_id = {
      description = "Free individual access with AWS Builder ID"
      setup_url   = "https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/auth-builder-id.html"
      cost        = "Free with usage limits"
    }
    iam_identity_center = {
      description = "Enterprise access with IAM Identity Center (Pro subscription required)"
      setup_url   = "https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/auth-iam-ic.html"
      cost        = "$19/user/month"
      enabled     = var.enable_identity_center
    }
  }
}

# Feature Configuration Outputs
output "enabled_features" {
  description = "Summary of enabled Amazon Q Developer features"
  value = {
    admin_role_created       = var.create_admin_role
    user_role_created        = var.create_user_role
    identity_center_enabled  = var.enable_identity_center
    usage_monitoring_enabled = var.enable_usage_monitoring
    config_bucket_created    = var.create_config_bucket
    cost_alerts_enabled      = var.enable_cost_alerts
    backup_enabled           = var.enable_backup
  }
}

# Integration Information Outputs
output "integration_endpoints" {
  description = "API endpoints and integration information for Amazon Q Developer"
  value = {
    amazon_q_service_endpoint = "https://q.${data.aws_region.current.name}.amazonaws.com"
    codewhisperer_endpoint    = "https://codewhisperer.${data.aws_region.current.name}.amazonaws.com"
    vs_code_marketplace_url   = "https://marketplace.visualstudio.com/items?itemName=AmazonWebServices.amazon-q-vscode"
  }
}

# Security and Compliance Outputs
output "security_configuration" {
  description = "Security configuration summary for Amazon Q Developer"
  value = {
    encryption_enabled     = var.enable_encryption
    allowed_ip_ranges     = var.allowed_ip_ranges
    session_duration      = var.enable_identity_center ? var.session_duration : null
    trusted_user_arns     = var.trusted_user_arns
    public_access_blocked = var.create_config_bucket ? true : null
  }
}

# Cost Management Outputs
output "cost_management" {
  description = "Cost management configuration for Amazon Q Developer"
  value = {
    monthly_threshold_usd = var.enable_cost_alerts ? var.monthly_cost_threshold : null
    alert_email          = var.enable_cost_alerts ? var.cost_alert_email : null
    cost_alerts_enabled  = var.enable_cost_alerts
    estimated_monthly_cost = {
      free_tier = "Free with AWS Builder ID (generous limits)"
      pro_tier  = "${var.enable_identity_center ? length(var.identity_center_user_ids) * 19 : 0} USD/month for IAM Identity Center users"
    }
  }
}

# Workspace Configuration Outputs
output "workspace_configuration" {
  description = "Amazon Q Developer workspace configuration settings"
  value = {
    code_suggestions_enabled    = var.workspace_settings.enable_code_suggestions
    security_scanning_enabled   = var.workspace_settings.enable_security_scanning
    code_explanations_enabled   = var.workspace_settings.enable_code_explanations
    suggestion_threshold        = var.workspace_settings.suggestion_threshold
    max_suggestions_per_minute  = var.workspace_settings.max_suggestions_per_minute
  }
}

# Quick Start Guide Output
output "quick_start_guide" {
  description = "Quick start steps for Amazon Q Developer setup"
  value = {
    step_1 = "Install VS Code extension: ${local.vs_code_extension_command}"
    step_2 = "Open VS Code and click the Amazon Q icon in the activity bar"
    step_3 = "Choose authentication method: AWS Builder ID (free) or IAM Identity Center (Pro)"
    step_4 = "Complete authentication flow in browser"
    step_5 = "Return to VS Code and start coding with AI assistance"
    documentation = "https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/"
  }
}

# Resource Tags Output
output "applied_tags" {
  description = "Tags applied to all Amazon Q Developer resources"
  value = merge(
    {
      Project     = "Amazon Q Developer"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.team_tags
  )
}

# Troubleshooting Information Output
output "troubleshooting_info" {
  description = "Troubleshooting information for Amazon Q Developer setup"
  value = {
    common_issues = {
      authentication_failed = "Verify AWS credentials and region settings"
      no_suggestions       = "Check VS Code extension is enabled and authenticated"
      permission_denied    = "Verify IAM roles and policies are correctly configured"
      rate_limited        = "Check usage limits for your authentication method"
    }
    support_resources = {
      documentation = "https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/"
      troubleshooting = "https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/troubleshooting.html"
      aws_support = "https://aws.amazon.com/support/"
    }
    log_locations = {
      vs_code_logs = "VS Code Command Palette > 'Developer: Open Logs Folder'"
      cloudwatch_logs = var.enable_usage_monitoring ? aws_cloudwatch_log_group.amazon_q_usage_logs[0].name : "Not enabled"
    }
  }
}

# Local Variables for Internal Use
locals {
  vs_code_extension_command = "code --install-extension AmazonWebServices.amazon-q-vscode"
}

# Version Information Output
output "terraform_version_info" {
  description = "Terraform version information for this deployment"
  value = {
    terraform_version = ">= 1.0"
    aws_provider_version = "~> 5.0"
    deployment_timestamp = timestamp()
  }
}