# =============================================================================
# OUTPUTS - AUTOMATED SECURITY SCANNING WITH INSPECTOR AND SECURITY HUB
# =============================================================================
# This file contains all the outputs from the automated security scanning
# infrastructure deployment, providing essential information for integration,
# monitoring, and management of the security pipeline.
# =============================================================================

# -----------------------------------------------------------------------------
# SECURITY HUB OUTPUTS
# -----------------------------------------------------------------------------

output "security_hub_arn" {
  description = "ARN of the AWS Security Hub account"
  value       = aws_securityhub_account.main.arn
}

output "security_hub_standards" {
  description = "List of enabled Security Hub standards with their ARNs"
  value = {
    aws_foundational = aws_securityhub_standards_subscription.aws_foundational.standards_arn
    cis_benchmark   = aws_securityhub_standards_subscription.cis_benchmark.standards_arn
  }
}

output "security_hub_insights" {
  description = "Security Hub custom insights for monitoring critical vulnerabilities"
  value = {
    critical_vulnerabilities = {
      arn  = aws_securityhub_insight.critical_vulnerabilities.arn
      name = aws_securityhub_insight.critical_vulnerabilities.name
    }
    unpatched_ec2_instances = {
      arn  = aws_securityhub_insight.unpatched_ec2.arn
      name = aws_securityhub_insight.unpatched_ec2.name
    }
  }
}

# -----------------------------------------------------------------------------
# AMAZON INSPECTOR OUTPUTS
# -----------------------------------------------------------------------------

output "inspector_account_id" {
  description = "AWS account ID where Inspector is enabled"
  value       = data.aws_caller_identity.current.account_id
}

output "inspector_enabled_resource_types" {
  description = "List of resource types enabled for Inspector scanning"
  value       = var.inspector_resource_types
}

output "inspector_enabler_arn" {
  description = "ARN of the Inspector enabler resource"
  value       = aws_inspector2_enabler.main.id
}

# -----------------------------------------------------------------------------
# SNS AND NOTIFICATION OUTPUTS
# -----------------------------------------------------------------------------

output "security_alerts_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "security_alerts_topic_name" {
  description = "Name of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.name
}

output "email_subscription_arn" {
  description = "ARN of the email subscription to security alerts (if email provided)"
  value       = var.notification_email != "" ? aws_sns_topic_subscription.email_alerts[0].arn : null
}

output "email_subscription_status" {
  description = "Status of email subscription setup"
  value = var.notification_email != "" ? {
    email_configured     = true
    subscription_pending = true
    message             = "Check email for subscription confirmation"
  } : {
    email_configured     = false
    subscription_pending = false
    message             = "No email address provided"
  }
}

# -----------------------------------------------------------------------------
# LAMBDA FUNCTION OUTPUTS
# -----------------------------------------------------------------------------

output "security_response_handler_function" {
  description = "Details of the security response handler Lambda function"
  value = {
    arn           = aws_lambda_function.security_response_handler.arn
    function_name = aws_lambda_function.security_response_handler.function_name
    role_arn      = aws_iam_role.lambda_security_response.arn
    log_group     = aws_cloudwatch_log_group.security_response_handler.name
  }
}

output "compliance_report_generator_function" {
  description = "Details of the compliance report generator Lambda function"
  value = {
    arn           = aws_lambda_function.compliance_report_generator.arn
    function_name = aws_lambda_function.compliance_report_generator.function_name
    role_arn      = aws_iam_role.lambda_compliance_reporting.arn
    log_group     = aws_cloudwatch_log_group.compliance_report_generator.name
  }
}

# -----------------------------------------------------------------------------
# EVENTBRIDGE OUTPUTS
# -----------------------------------------------------------------------------

output "security_findings_rule" {
  description = "EventBridge rule for processing security findings"
  value = {
    name = aws_cloudwatch_event_rule.security_findings.name
    arn  = aws_cloudwatch_event_rule.security_findings.arn
  }
}

output "compliance_report_schedule_rule" {
  description = "EventBridge rule for scheduled compliance reporting"
  value = {
    name     = aws_cloudwatch_event_rule.weekly_compliance_report.name
    arn      = aws_cloudwatch_event_rule.weekly_compliance_report.arn
    schedule = var.compliance_report_schedule
  }
}

# -----------------------------------------------------------------------------
# S3 BUCKET OUTPUTS
# -----------------------------------------------------------------------------

output "compliance_reports_bucket" {
  description = "S3 bucket for storing compliance reports"
  value = {
    name                = aws_s3_bucket.compliance_reports.id
    arn                 = aws_s3_bucket.compliance_reports.arn
    bucket_domain_name  = aws_s3_bucket.compliance_reports.bucket_domain_name
    region             = aws_s3_bucket.compliance_reports.region
    versioning_enabled = aws_s3_bucket_versioning.compliance_reports.versioning_configuration[0].status
  }
}

# -----------------------------------------------------------------------------
# IAM ROLE OUTPUTS
# -----------------------------------------------------------------------------

output "lambda_execution_roles" {
  description = "IAM roles for Lambda function execution"
  value = {
    security_response_role = {
      name = aws_iam_role.lambda_security_response.name
      arn  = aws_iam_role.lambda_security_response.arn
    }
    compliance_reporting_role = {
      name = aws_iam_role.lambda_compliance_reporting.name
      arn  = aws_iam_role.lambda_compliance_reporting.arn
    }
  }
}

# -----------------------------------------------------------------------------
# TEST INSTANCE OUTPUTS (IF CREATED)
# -----------------------------------------------------------------------------

output "test_instance" {
  description = "Details of the test EC2 instance (if created)"
  value = var.create_test_instance ? {
    instance_id     = aws_instance.test_instance[0].id
    public_ip       = aws_instance.test_instance[0].public_ip
    private_ip      = aws_instance.test_instance[0].private_ip
    security_group  = aws_security_group.test_instance[0].id
    ami_id         = aws_instance.test_instance[0].ami
    instance_type  = aws_instance.test_instance[0].instance_type
    availability_zone = aws_instance.test_instance[0].availability_zone
  } : null
}

# -----------------------------------------------------------------------------
# CLOUDWATCH DASHBOARD OUTPUTS
# -----------------------------------------------------------------------------

output "security_monitoring_dashboard" {
  description = "CloudWatch dashboard for security monitoring"
  value = {
    name = aws_cloudwatch_dashboard.security_monitoring.dashboard_name
    url  = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.security_monitoring.dashboard_name}"
  }
}

# -----------------------------------------------------------------------------
# DEPLOYMENT INFORMATION
# -----------------------------------------------------------------------------

output "deployment_region" {
  description = "AWS region where the security scanning infrastructure is deployed"
  value       = data.aws_region.current.name
}

output "deployment_account" {
  description = "AWS account ID where the security scanning infrastructure is deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Prefix used for all resource names"
  value       = var.resource_prefix
}

# -----------------------------------------------------------------------------
# CONFIGURATION SUMMARY
# -----------------------------------------------------------------------------

output "configuration_summary" {
  description = "Summary of the deployed security scanning configuration"
  value = {
    # Security Hub Configuration
    security_hub_enabled         = true
    default_standards_enabled    = var.enable_default_standards
    organization_management      = var.enable_organization_management
    
    # Inspector Configuration
    inspector_enabled           = true
    inspector_resource_types    = var.inspector_resource_types
    inspector_scan_mode        = var.inspector_scan_mode
    ecr_rescan_duration        = var.ecr_rescan_duration
    
    # Alerting Configuration
    email_notifications_enabled = var.notification_email != ""
    alert_severity_levels       = var.alert_severity_levels
    
    # Compliance Reporting
    compliance_reporting_enabled = true
    compliance_report_schedule  = var.compliance_report_schedule
    reports_retention_days      = var.compliance_reports_retention_days
    
    # Test Infrastructure
    test_instance_created = var.create_test_instance
    
    # Enhanced Features
    cloudwatch_dashboard_enabled = var.create_cloudwatch_dashboard
    auto_remediation_enabled     = var.auto_remediation_enabled
  }
}

# -----------------------------------------------------------------------------
# NEXT STEPS AND COMMANDS
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Next steps and useful commands for managing the security scanning infrastructure"
  value = {
    verify_security_hub = "aws securityhub get-enabled-standards --region ${data.aws_region.current.name}"
    check_inspector_coverage = "aws inspector2 get-coverage-statistics --region ${data.aws_region.current.name}"
    view_recent_findings = "aws securityhub get-findings --region ${data.aws_region.current.name} --max-items 10"
    test_lambda_function = "aws lambda invoke --function-name ${aws_lambda_function.security_response_handler.function_name} --region ${data.aws_region.current.name} /tmp/response.json"
    view_compliance_reports = "aws s3 ls s3://${aws_s3_bucket.compliance_reports.id}/compliance-reports/"
    cloudwatch_logs_security = "aws logs describe-log-groups --log-group-name-prefix /aws/lambda/${var.resource_prefix} --region ${data.aws_region.current.name}"
  }
}

# -----------------------------------------------------------------------------
# IMPORTANT URLS AND CONSOLE LINKS
# -----------------------------------------------------------------------------

output "console_urls" {
  description = "AWS Console URLs for managing and monitoring the security scanning infrastructure"
  value = {
    security_hub_console = "https://${data.aws_region.current.name}.console.aws.amazon.com/securityhub/home?region=${data.aws_region.current.name}#/"
    inspector_console    = "https://${data.aws_region.current.name}.console.aws.amazon.com/inspector/v2/home?region=${data.aws_region.current.name}"
    lambda_console       = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions"
    cloudwatch_console   = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}"
    eventbridge_console  = "https://${data.aws_region.current.name}.console.aws.amazon.com/events/home?region=${data.aws_region.current.name}#/"
    s3_console          = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.compliance_reports.id}?region=${data.aws_region.current.name}"
    sns_console         = "https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home?region=${data.aws_region.current.name}#/topic/${aws_sns_topic.security_alerts.arn}"
  }
}

# -----------------------------------------------------------------------------
# COST INFORMATION
# -----------------------------------------------------------------------------

output "cost_information" {
  description = "Estimated monthly costs and cost optimization information"
  value = {
    estimated_monthly_cost = "Estimated $50-100/month for 50 EC2 instances, 20 ECR repositories, and 10 Lambda functions"
    cost_factors = [
      "Amazon Inspector charges based on resources scanned",
      "Security Hub charges based on findings ingested and compliance checks",
      "Lambda execution costs based on invocations and duration",
      "S3 storage costs for compliance reports",
      "CloudWatch Logs retention costs"
    ]
    cost_optimization_tips = [
      "Use Inspector resource filtering to scan only critical resources",
      "Adjust compliance report retention period based on requirements",
      "Monitor Lambda execution metrics to optimize memory allocation",
      "Consider S3 lifecycle policies for older compliance reports"
    ]
  }
}

# -----------------------------------------------------------------------------
# SECURITY CONSIDERATIONS
# -----------------------------------------------------------------------------

output "security_considerations" {
  description = "Important security considerations and recommendations"
  value = {
    immediate_actions = [
      "Confirm email subscription to receive security alerts",
      "Review and customize alert severity levels based on requirements",
      "Test EventBridge rules with sample security findings",
      "Verify IAM roles follow least privilege principle"
    ]
    ongoing_maintenance = [
      "Regularly review Security Hub findings and remediate critical issues",
      "Monitor Lambda function logs for any processing errors",
      "Update Lambda function code as security requirements evolve",
      "Review and update Security Hub standards subscriptions quarterly"
    ]
    security_best_practices = [
      "Enable AWS CloudTrail for audit logging of security service API calls",
      "Use AWS Config for configuration compliance monitoring",
      "Implement network security groups and NACLs for test instances",
      "Regularly rotate IAM access keys and review permissions"
    ]
  }
}