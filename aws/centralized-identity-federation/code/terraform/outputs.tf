# Core Identity Center Outputs
output "sso_instance_arn" {
  description = "ARN of the IAM Identity Center instance"
  value       = local.sso_instance_arn
}

output "sso_identity_store_id" {
  description = "Identity Store ID for the IAM Identity Center instance"
  value       = local.sso_identity_store_id
}

output "sso_aws_access_portal_url" {
  description = "AWS access portal URL for the IAM Identity Center instance"
  value       = try(data.aws_ssoadmin_instances.current.identity_store_ids[0] != null ? "https://${split("/", data.aws_ssoadmin_instances.current.arns[0])[1]}.awsapps.com/start" : "Please check AWS Console for access portal URL", "Please check AWS Console for access portal URL")
}

# Permission Set Outputs
output "permission_sets" {
  description = "Map of permission set names to their ARNs and details"
  value = {
    for key, ps in aws_ssoadmin_permission_set.permission_sets : key => {
      arn             = ps.arn
      name            = ps.name
      description     = ps.description
      session_duration = ps.session_duration
    }
  }
  sensitive = false
}

output "permission_set_arns" {
  description = "List of permission set ARNs"
  value       = [for ps in aws_ssoadmin_permission_set.permission_sets : ps.arn]
}

# Account Assignment Outputs
output "account_assignments" {
  description = "Map of account assignments with their details"
  value = {
    for key, assignment in aws_ssoadmin_account_assignment.account_assignments : key => {
      account_id         = assignment.target_id
      permission_set_arn = assignment.permission_set_arn
      principal_type     = assignment.principal_type
      principal_id       = assignment.principal_id
    }
  }
  sensitive = true
}

output "account_assignment_count" {
  description = "Total number of account assignments created"
  value       = length(aws_ssoadmin_account_assignment.account_assignments)
}

# Application Outputs
output "saml_applications" {
  description = "Map of SAML applications with their details"
  value = {
    for key, app in aws_ssoadmin_application.saml_applications : key => {
      arn                = app.arn
      name              = app.name
      description       = app.description
      application_account = app.application_account
      application_arn    = app.application_arn
      status            = app.status
    }
  }
}

output "application_count" {
  description = "Total number of SAML applications configured"
  value       = length(aws_ssoadmin_application.saml_applications)
}

# CloudTrail and Audit Outputs
output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for audit logging"
  value       = var.enable_cloudtrail ? aws_cloudtrail.identity_federation_audit[0].arn : null
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket name for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

output "audit_log_group_name" {
  description = "CloudWatch log group name for SSO audit logs"
  value       = aws_cloudwatch_log_group.sso_audit_logs.name
}

output "audit_log_group_arn" {
  description = "CloudWatch log group ARN for SSO audit logs"
  value       = aws_cloudwatch_log_group.sso_audit_logs.arn
}

# Monitoring and Alerting Outputs
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${local.region_name}.console.aws.amazon.com/cloudwatch/home?region=${local.region_name}#dashboards:name=${aws_cloudwatch_dashboard.identity_federation[0].dashboard_name}" : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = var.enable_cloudwatch_alarms && var.alarm_notification_email != "" ? aws_sns_topic.identity_alerts[0].arn : null
}

output "cloudwatch_alarms" {
  description = "Map of CloudWatch alarms created"
  value = var.enable_cloudwatch_alarms ? {
    sign_in_failures = aws_cloudwatch_metric_alarm.sso_sign_in_failures[0].alarm_name
    unusual_activity = aws_cloudwatch_metric_alarm.unusual_sign_in_activity[0].alarm_name
  } : {}
}

# Disaster Recovery Outputs
output "disaster_recovery_document_name" {
  description = "Name of the Systems Manager document for disaster recovery"
  value       = var.enable_backup_configuration ? aws_ssm_document.disaster_recovery_runbook[0].name : null
}

output "backup_regions" {
  description = "List of regions configured for backup"
  value       = var.backup_regions
}

# Security and Compliance Outputs
output "mfa_required" {
  description = "Whether MFA is required for authentication"
  value       = var.require_mfa
}

output "trusted_device_management_enabled" {
  description = "Whether trusted device management is enabled"
  value       = var.enable_trusted_device_management
}

output "session_timeout_configured" {
  description = "Default session timeout configured"
  value       = var.session_timeout
}

# Resource Information
output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = local.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = local.region_name
}

output "organization_id" {
  description = "AWS Organizations ID"
  value       = data.aws_organizations_organization.current.id
}

output "organization_master_account_id" {
  description = "AWS Organizations master account ID"
  value       = data.aws_organizations_organization.current.master_account_id
}

# Testing and Development Outputs (only in dev environment)
output "test_user_details" {
  description = "Details of test user created (dev environment only)"
  value = var.environment == "dev" ? {
    user_id    = aws_identitystore_user.admin_user[0].user_id
    username   = aws_identitystore_user.admin_user[0].user_name
    group_id   = aws_identitystore_group.admin_group[0].group_id
    group_name = aws_identitystore_group.admin_group[0].display_name
  } : null
  sensitive = true
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Quick Start Information
output "quick_start_info" {
  description = "Quick start information for getting started with the identity federation"
  value = {
    aws_access_portal_url = try(data.aws_ssoadmin_instances.current.identity_store_ids[0] != null ? "https://${split("/", data.aws_ssoadmin_instances.current.arns[0])[1]}.awsapps.com/start" : "Please check AWS Console for access portal URL", "Please check AWS Console for access portal URL")
    permission_sets_created = length(aws_ssoadmin_permission_set.permission_sets)
    account_assignments_created = length(aws_ssoadmin_account_assignment.account_assignments)
    applications_configured = length(aws_ssoadmin_application.saml_applications)
    cloudtrail_enabled = var.enable_cloudtrail
    monitoring_enabled = var.enable_cloudwatch_dashboard
    next_steps = [
      "1. Configure your external identity provider with the SAML metadata",
      "2. Create users and groups in your identity store",
      "3. Test user authentication and access to assigned accounts",
      "4. Review CloudWatch dashboard for monitoring insights",
      "5. Configure additional SAML applications as needed"
    ]
  }
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (approximate)"
  value = {
    identity_center = "Free (up to 5 GB of audit logs)"
    cloudtrail = var.enable_cloudtrail ? "$2.00 per 100,000 events" : "Disabled"
    s3_storage = var.enable_cloudtrail ? "$0.023 per GB stored" : "Disabled"
    cloudwatch_logs = "$0.50 per GB ingested + $0.03 per GB stored"
    cloudwatch_dashboard = var.enable_cloudwatch_dashboard ? "$3.00 per dashboard" : "Disabled"
    sns_notifications = var.alarm_notification_email != "" ? "$0.50 per 1M notifications" : "Disabled"
    total_estimated = "~$5-15 per month (varies with usage)"
  }
}

# Compliance and Security Status
output "compliance_status" {
  description = "Compliance and security features enabled"
  value = {
    audit_logging_enabled = var.enable_cloudtrail
    mfa_enforcement = var.require_mfa
    session_timeout_configured = var.session_timeout
    trusted_device_management = var.enable_trusted_device_management
    encryption_at_rest = var.enable_cloudtrail ? "S3 bucket encrypted with AES256" : "N/A"
    least_privilege_access = "Enforced through permission sets"
    centralized_identity_management = "Enabled with IAM Identity Center"
  }
}