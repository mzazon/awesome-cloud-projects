# ==============================================================================
# ZERO TRUST SECURITY ARCHITECTURE - TERRAFORM OUTPUTS
# ==============================================================================

# General Information
output "account_id" {
  description = "AWS Account ID"
  value       = local.account_id
}

output "region" {
  description = "AWS Region"
  value       = local.region
}

output "resource_prefix" {
  description = "Resource prefix used for naming"
  value       = local.resource_prefix
}

# ==============================================================================
# KMS OUTPUTS
# ==============================================================================

output "kms_key_id" {
  description = "ID of the KMS key for zero trust encryption"
  value       = aws_kms_key.zero_trust.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for zero trust encryption"
  value       = aws_kms_key.zero_trust.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key for zero trust encryption"
  value       = aws_kms_alias.zero_trust.name
}

# ==============================================================================
# S3 OUTPUTS
# ==============================================================================

output "security_logs_bucket" {
  description = "Name of the S3 bucket for security logs"
  value       = aws_s3_bucket.security_logs.id
}

output "security_logs_bucket_arn" {
  description = "ARN of the S3 bucket for security logs"
  value       = aws_s3_bucket.security_logs.arn
}

output "secure_data_bucket" {
  description = "Name of the S3 bucket for secure data"
  value       = aws_s3_bucket.secure_data.id
}

output "secure_data_bucket_arn" {
  description = "ARN of the S3 bucket for secure data"
  value       = aws_s3_bucket.secure_data.arn
}

# ==============================================================================
# NETWORK OUTPUTS
# ==============================================================================

output "vpc_id" {
  description = "ID of the zero trust VPC"
  value       = aws_vpc.zero_trust.id
}

output "vpc_cidr" {
  description = "CIDR block of the zero trust VPC"
  value       = aws_vpc.zero_trust.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "zero_trust_security_group_id" {
  description = "ID of the zero trust security group"
  value       = aws_security_group.zero_trust.id
}

output "vpc_endpoints" {
  description = "VPC endpoint information"
  value = {
    s3_endpoint_id   = aws_vpc_endpoint.s3.id
    logs_endpoint_id = aws_vpc_endpoint.logs.id
  }
}

# ==============================================================================
# SECURITY SERVICES OUTPUTS
# ==============================================================================

output "security_hub" {
  description = "Security Hub configuration"
  value = var.enable_security_hub ? {
    account_id                = aws_securityhub_account.main[0].id
    aws_foundational_arn      = length(aws_securityhub_standards_subscription.aws_foundational) > 0 ? aws_securityhub_standards_subscription.aws_foundational[0].standards_arn : null
    cis_benchmark_arn         = length(aws_securityhub_standards_subscription.cis) > 0 ? aws_securityhub_standards_subscription.cis[0].standards_arn : null
    high_risk_insight_arn     = length(aws_securityhub_insight.zero_trust_high_risk) > 0 ? aws_securityhub_insight.zero_trust_high_risk[0].arn : null
  } : null
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "guardduty_detector_arn" {
  description = "GuardDuty detector ARN"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].arn : null
}

output "config_recorder_name" {
  description = "AWS Config recorder name"
  value       = var.enable_config ? aws_config_configuration_recorder.main[0].name : null
}

output "config_delivery_channel_name" {
  description = "AWS Config delivery channel name"
  value       = var.enable_config ? aws_config_delivery_channel.main[0].name : null
}

output "inspector_enabler_id" {
  description = "Amazon Inspector enabler ID"
  value       = var.enable_inspector ? aws_inspector2_enabler.main[0].id : null
}

# ==============================================================================
# IAM OUTPUTS
# ==============================================================================

output "zero_trust_boundary_policy_arn" {
  description = "ARN of the zero trust boundary policy"
  value       = aws_iam_policy.zero_trust_boundary.arn
}

output "abac_policy_arn" {
  description = "ARN of the ABAC policy"
  value       = aws_iam_policy.abac.arn
}

output "security_role_arn" {
  description = "ARN of the security role"
  value       = aws_iam_role.security.arn
}

output "config_role_arn" {
  description = "ARN of the Config service role"
  value       = var.enable_config ? aws_iam_role.config[0].arn : null
}

output "flow_logs_role_arn" {
  description = "ARN of the VPC Flow Logs role"
  value       = var.enable_vpc_flow_logs ? aws_iam_role.flow_logs[0].arn : null
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "cloudwatch_log_groups" {
  description = "CloudWatch log group information"
  value = {
    zero_trust_log_group    = aws_cloudwatch_log_group.zero_trust.name
    vpc_flow_logs_group     = var.enable_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
    session_logs_group      = aws_cloudwatch_log_group.session_logs.name
  }
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.zero_trust.dashboard_name}"
}

output "failed_logins_alarm_arn" {
  description = "ARN of the failed logins CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.failed_logins.arn
}

# ==============================================================================
# LAMBDA OUTPUTS
# ==============================================================================

output "session_verification_lambda" {
  description = "Session verification Lambda function information"
  value = {
    function_name = aws_lambda_function.session_verification.function_name
    function_arn  = aws_lambda_function.session_verification.arn
    invoke_arn    = aws_lambda_function.session_verification.invoke_arn
  }
}

# ==============================================================================
# COST MONITORING OUTPUTS
# ==============================================================================

output "cost_anomaly_detector" {
  description = "Cost anomaly detector information"
  value = var.enable_cost_anomaly_detection ? {
    detector_arn      = aws_ce_anomaly_detector.zero_trust[0].arn
    subscription_arn  = aws_ce_anomaly_subscription.zero_trust[0].arn
  } : null
}

# ==============================================================================
# SECURITY COMPLIANCE OUTPUTS
# ==============================================================================

output "config_rules" {
  description = "AWS Config rules for zero trust compliance"
  value = var.enable_config ? {
    mfa_enabled_rule         = aws_config_config_rule.mfa_enabled[0].name
    s3_ssl_requests_rule     = aws_config_config_rule.s3_ssl_requests_only[0].name
  } : null
}

# ==============================================================================
# VALIDATION COMMANDS
# ==============================================================================

output "validation_commands" {
  description = "Commands to validate the zero trust architecture deployment"
  value = {
    check_security_hub = "aws securityhub get-enabled-standards --region ${local.region}"
    check_guardduty    = var.enable_guardduty ? "aws guardduty get-detector --detector-id ${aws_guardduty_detector.main[0].id} --region ${local.region}" : "GuardDuty not enabled"
    check_config       = var.enable_config ? "aws configservice describe-configuration-recorders --region ${local.region}" : "Config not enabled"
    check_vpc_flow_logs = var.enable_vpc_flow_logs ? "aws ec2 describe-flow-logs --filter Name=resource-id,Values=${aws_vpc.zero_trust.id} --region ${local.region}" : "VPC Flow Logs not enabled"
    check_s3_encryption = "aws s3api get-bucket-encryption --bucket ${aws_s3_bucket.security_logs.id} --region ${local.region}"
    test_lambda        = "aws lambda invoke --function-name ${aws_lambda_function.session_verification.function_name} --payload '{}' response.json --region ${local.region}"
  }
}

# ==============================================================================
# SECURITY URLS
# ==============================================================================

output "security_console_urls" {
  description = "URLs to AWS security consoles"
  value = {
    security_hub    = "https://${local.region}.console.aws.amazon.com/securityhub/home?region=${local.region}#/summary"
    guardduty       = "https://${local.region}.console.aws.amazon.com/guardduty/home?region=${local.region}#/findings"
    config          = "https://${local.region}.console.aws.amazon.com/config/home?region=${local.region}#/dashboard"
    inspector       = "https://${local.region}.console.aws.amazon.com/inspector/v2/home?region=${local.region}#/dashboard"
    cloudtrail      = "https://${local.region}.console.aws.amazon.com/cloudtrail/home?region=${local.region}#/events"
    iam             = "https://console.aws.amazon.com/iam/home#/home"
    cost_explorer   = "https://console.aws.amazon.com/cost-management/home#/cost-explorer"
  }
}

# ==============================================================================
# NEXT STEPS
# ==============================================================================

output "next_steps" {
  description = "Next steps to complete the zero trust configuration"
  value = [
    "1. Configure IAM Identity Center at: https://console.aws.amazon.com/singlesignon/home",
    "2. Set up SAML identity provider integration for federated access",
    "3. Create permission sets with the zero trust boundary policy: ${aws_iam_policy.zero_trust_boundary.arn}",
    "4. Configure MFA for all IAM users and Identity Center users",
    "5. Review and customize the ABAC policy: ${aws_iam_policy.abac.arn}",
    "6. Set up monitoring alerts and review the dashboard: ${aws_cloudwatch_dashboard.zero_trust.dashboard_name}",
    "7. Test the session verification Lambda function: ${aws_lambda_function.session_verification.function_name}",
    "8. Configure trusted IP ranges in variables.tf: ${jsonencode(var.trusted_ip_ranges)}",
    "9. Subscribe to security alerts SNS topic: ${aws_sns_topic.security_alerts.arn}",
    "10. Review cost anomaly alerts and adjust thresholds as needed"
  ]
}

# ==============================================================================
# TERRAFORM STATE INFORMATION
# ==============================================================================

output "terraform_state_info" {
  description = "Information about the Terraform state and resources created"
  value = {
    resource_count       = length([for k, v in data.terraform_remote_state.this : k])
    deployment_timestamp = timestamp()
    terraform_version    = ">= 1.0"
    aws_provider_version = "~> 5.0"
  }
}

# Reference to terraform state (for resource counting)
data "terraform_remote_state" "this" {
  backend = "local"
  config = {
    path = "${path.module}/terraform.tfstate"
  }
}