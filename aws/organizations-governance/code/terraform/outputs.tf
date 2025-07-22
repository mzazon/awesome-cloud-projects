# Outputs for multi-account governance infrastructure

# Organization Information
output "organization_id" {
  description = "The organization ID"
  value       = aws_organizations_organization.main.id
}

output "organization_arn" {
  description = "The organization ARN"
  value       = aws_organizations_organization.main.arn
}

output "organization_master_account_id" {
  description = "The master account ID of the organization"
  value       = aws_organizations_organization.main.master_account_id
}

output "organization_master_account_email" {
  description = "The master account email of the organization"
  value       = aws_organizations_organization.main.master_account_email
}

output "organization_root_id" {
  description = "The root ID of the organization"
  value       = aws_organizations_organization.main.roots[0].id
}

# Organizational Units
output "production_ou_id" {
  description = "The Production Organizational Unit ID"
  value       = aws_organizations_organizational_unit.production.id
}

output "production_ou_arn" {
  description = "The Production Organizational Unit ARN"
  value       = aws_organizations_organizational_unit.production.arn
}

output "development_ou_id" {
  description = "The Development Organizational Unit ID"
  value       = aws_organizations_organizational_unit.development.id
}

output "development_ou_arn" {
  description = "The Development Organizational Unit ARN"
  value       = aws_organizations_organizational_unit.development.arn
}

output "sandbox_ou_id" {
  description = "The Sandbox Organizational Unit ID"
  value       = aws_organizations_organizational_unit.sandbox.id
}

output "sandbox_ou_arn" {
  description = "The Sandbox Organizational Unit ARN"
  value       = aws_organizations_organizational_unit.sandbox.arn
}

output "security_ou_id" {
  description = "The Security Organizational Unit ID"
  value       = aws_organizations_organizational_unit.security.id
}

output "security_ou_arn" {
  description = "The Security Organizational Unit ARN"
  value       = aws_organizations_organizational_unit.security.arn
}

# Service Control Policies
output "cost_control_policy_id" {
  description = "The Cost Control Policy ID"
  value       = aws_organizations_policy.cost_control.id
}

output "cost_control_policy_arn" {
  description = "The Cost Control Policy ARN"
  value       = aws_organizations_policy.cost_control.arn
}

output "security_baseline_policy_id" {
  description = "The Security Baseline Policy ID"
  value       = aws_organizations_policy.security_baseline.id
}

output "security_baseline_policy_arn" {
  description = "The Security Baseline Policy ARN"
  value       = aws_organizations_policy.security_baseline.arn
}

output "region_restriction_policy_id" {
  description = "The Region Restriction Policy ID"
  value       = aws_organizations_policy.region_restriction.id
}

output "region_restriction_policy_arn" {
  description = "The Region Restriction Policy ARN"
  value       = aws_organizations_policy.region_restriction.arn
}

# CloudTrail Information
output "cloudtrail_arn" {
  description = "The ARN of the organization CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.organization[0].arn : null
}

output "cloudtrail_s3_bucket" {
  description = "The S3 bucket name for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].bucket : null
}

output "cloudtrail_s3_bucket_arn" {
  description = "The S3 bucket ARN for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].arn : null
}

# Monitoring Information
output "cloudwatch_dashboard_name" {
  description = "The name of the CloudWatch governance dashboard"
  value       = aws_cloudwatch_dashboard.governance.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "The URL of the CloudWatch governance dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.governance.dashboard_name}"
}

# Budget Information
output "budget_name" {
  description = "The name of the organization budget"
  value       = aws_budgets_budget.organization.name
}

output "budget_amount" {
  description = "The budget amount in USD"
  value       = "${aws_budgets_budget.organization.limit_amount} ${aws_budgets_budget.organization.limit_unit}"
}

# Cost Anomaly Detection
output "cost_anomaly_detector_arn" {
  description = "The ARN of the cost anomaly detector"
  value       = var.enable_cost_anomaly_detection ? aws_ce_anomaly_detector.organization[0].arn : null
}

# Member Accounts (if created)
output "member_accounts" {
  description = "Information about created member accounts"
  value = var.create_member_accounts ? [
    for account in aws_organizations_account.member : {
      id     = account.id
      name   = account.name
      email  = account.email
      status = account.status
      arn    = account.arn
    }
  ] : []
}

# Policy Attachments Summary
output "policy_attachments" {
  description = "Summary of policy attachments to organizational units"
  value = {
    cost_control_attachments = [
      {
        policy_name = aws_organizations_policy.cost_control.name
        ou_name     = "Production"
        ou_id       = aws_organizations_organizational_unit.production.id
      },
      {
        policy_name = aws_organizations_policy.cost_control.name
        ou_name     = "Development" 
        ou_id       = aws_organizations_organizational_unit.development.id
      }
    ]
    security_baseline_attachments = [
      {
        policy_name = aws_organizations_policy.security_baseline.name
        ou_name     = "Production"
        ou_id       = aws_organizations_organizational_unit.production.id
      }
    ]
    region_restriction_attachments = [
      {
        policy_name = aws_organizations_policy.region_restriction.name
        ou_name     = "Sandbox"
        ou_id       = aws_organizations_organizational_unit.sandbox.id
      }
    ]
  }
}

# Summary Information
output "governance_summary" {
  description = "Summary of the governance framework"
  value = {
    organization_id     = aws_organizations_organization.main.id
    total_ous          = 4
    total_policies     = 3
    cloudtrail_enabled = var.enable_cloudtrail
    config_enabled     = var.enable_config
    budget_configured  = true
    anomaly_detection  = var.enable_cost_anomaly_detection
    allowed_regions    = var.allowed_regions
    required_tags      = var.required_tags
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    create_member_accounts   = "Create and move member accounts to appropriate OUs"
    configure_sso           = "Set up AWS SSO for centralized access management"
    enable_config           = "Enable AWS Config for compliance monitoring"
    setup_security_hub      = "Configure Security Hub for centralized security findings"
    implement_monitoring    = "Set up additional CloudWatch alarms and notifications"
    test_policies          = "Test Service Control Policies in non-production environments"
    dashboard_url          = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.governance.dashboard_name}"
  }
}