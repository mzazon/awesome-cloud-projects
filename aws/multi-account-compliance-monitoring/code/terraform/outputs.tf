# Output values for the cross-account compliance monitoring solution

# Security Hub Configuration
output "security_hub_arn" {
  description = "ARN of the Security Hub account"
  value       = aws_securityhub_account.main.arn
}

output "security_hub_member_accounts" {
  description = "List of Security Hub member account IDs"
  value       = [for member in aws_securityhub_member.members : member.account_id]
}

# Cross-Account Role Information
output "cross_account_role_arn" {
  description = "ARN of the cross-account compliance role in the security account"
  value       = aws_iam_role.cross_account_compliance.arn
}

output "member_account_1_role_arn" {
  description = "ARN of the compliance role in member account 1"
  value       = aws_iam_role.member_compliance_role_1.arn
}

output "member_account_2_role_arn" {
  description = "ARN of the compliance role in member account 2"
  value       = aws_iam_role.member_compliance_role_2.arn
}

output "external_id" {
  description = "External ID for cross-account role assumption"
  value       = local.external_id
  sensitive   = true
}

# Lambda Function Information
output "compliance_processor_function_name" {
  description = "Name of the compliance processing Lambda function"
  value       = aws_lambda_function.compliance_processor.function_name
}

output "compliance_processor_function_arn" {
  description = "ARN of the compliance processing Lambda function"
  value       = aws_lambda_function.compliance_processor.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch Log Group name for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_compliance_processor.name
}

# CloudTrail Information
output "cloudtrail_name" {
  description = "Name of the CloudTrail for compliance auditing"
  value       = var.enable_cloudtrail ? aws_cloudtrail.compliance[0].name : null
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket name for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].bucket : null
}

output "cloudtrail_log_group_arn" {
  description = "CloudWatch Log Group ARN for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail[0].arn : null
}

# EventBridge Configuration
output "compliance_monitoring_rule_name" {
  description = "Name of the EventBridge rule for compliance monitoring"
  value       = aws_cloudwatch_event_rule.compliance_monitoring.name
}

output "security_hub_findings_rule_name" {
  description = "Name of the EventBridge rule for Security Hub findings"
  value       = aws_cloudwatch_event_rule.security_hub_findings.name
}

# Systems Manager Configuration
output "patch_baseline_linux_id" {
  description = "ID of the Linux patch baseline"
  value       = length(aws_ssm_patch_baseline.linux) > 0 ? aws_ssm_patch_baseline.linux[0].id : null
}

output "patch_baseline_windows_id" {
  description = "ID of the Windows patch baseline"
  value       = length(aws_ssm_patch_baseline.windows) > 0 ? aws_ssm_patch_baseline.windows[0].id : null
}

output "patch_compliance_association_id" {
  description = "ID of the patch compliance association"
  value       = aws_ssm_association.patch_compliance.association_id
}

output "custom_compliance_document_name" {
  description = "Name of the custom compliance Systems Manager document"
  value       = var.enable_custom_compliance ? aws_ssm_document.custom_compliance[0].name : null
}

# KMS Configuration
output "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.compliance[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key for encryption"
  value       = var.enable_kms_encryption ? aws_kms_alias.compliance[0].name : null
}

# SNS Configuration
output "sns_topic_arn" {
  description = "ARN of the SNS topic for compliance violation notifications"
  value       = var.notification_email != "" ? aws_sns_topic.compliance_violations[0].arn : null
}

# Resource Naming
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed compliance monitoring configuration"
  value = {
    security_account_id                = var.security_account_id
    member_accounts                    = local.all_member_accounts
    aws_region                        = var.aws_region
    environment                       = var.environment
    cloudtrail_enabled                = var.enable_cloudtrail
    kms_encryption_enabled            = var.enable_kms_encryption
    custom_compliance_enabled         = var.enable_custom_compliance
    notification_email_configured     = var.notification_email != ""
    compliance_check_schedule         = var.compliance_check_schedule
    lambda_timeout                    = var.lambda_timeout
    lambda_memory_size               = var.lambda_memory_size
    enabled_security_standards       = var.enable_security_standards
    required_tags                     = var.required_tags
    patch_baseline_operating_systems = var.patch_baseline_operating_systems
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_security_hub = "aws securityhub describe-hub"
    list_member_accounts = "aws securityhub list-members"
    check_lambda_function = "aws lambda get-function --function-name ${aws_lambda_function.compliance_processor.function_name}"
    test_cross_account_role = "aws sts assume-role --role-arn ${aws_iam_role.cross_account_compliance.arn} --role-session-name ComplianceTest --external-id ${local.external_id}"
    check_eventbridge_rules = "aws events list-rules --name-prefix ComplianceMonitoring"
    verify_cloudtrail = var.enable_cloudtrail ? "aws cloudtrail describe-trails --trail-name-list ${aws_cloudtrail.compliance[0].name}" : "CloudTrail not enabled"
    check_patch_baselines = "aws ssm describe-patch-baselines --max-results 10"
    list_compliance_summaries = "aws ssm list-compliance-summaries --max-results 5"
  }
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for the deployment"
  value = [
    "Regularly review and rotate the external ID for cross-account roles",
    "Monitor CloudTrail logs for unauthorized access attempts",
    "Set up CloudWatch alarms for Lambda function errors and throttling",
    "Regularly review Security Hub findings and implement remediation",
    "Enable AWS Config Rules for additional compliance checking",
    "Consider implementing AWS Organizations SCPs for preventive controls",
    "Review IAM policies regularly and apply principle of least privilege",
    "Enable AWS CloudTrail log file validation for integrity checking",
    "Set up regular compliance reporting and dashboard monitoring",
    "Implement automated remediation workflows for common violations"
  ]
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the compliance monitoring solution"
  value = [
    "Adjust Lambda memory allocation based on actual usage patterns",
    "Use S3 Intelligent Tiering for CloudTrail logs to reduce storage costs",
    "Set appropriate CloudWatch log retention periods",
    "Monitor and optimize Systems Manager association execution frequency",
    "Use AWS Cost Explorer to track compliance monitoring costs",
    "Consider using spot instances for non-critical compliance testing",
    "Implement lifecycle policies for S3 buckets containing compliance data",
    "Review and remove unused compliance rules and associations",
    "Use AWS Budgets to set cost alerts for compliance resources",
    "Optimize EventBridge rule filters to reduce unnecessary Lambda invocations"
  ]
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Configure Security Hub custom insights for compliance dashboards",
    "Set up additional member accounts using the established patterns",
    "Implement automated remediation workflows using Systems Manager Automation",
    "Create custom compliance rules for organization-specific requirements",
    "Set up regular compliance reporting and metrics collection",
    "Integrate with existing ITSM or ticketing systems",
    "Configure alerting and notification workflows",
    "Implement compliance score tracking and trending",
    "Set up regular compliance reviews and governance processes",
    "Consider implementing AWS Well-Architected compliance checking"
  ]
}