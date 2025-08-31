# General Outputs
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# SNS Topic Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for compliance notifications"
  value       = aws_sns_topic.compliance_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for compliance notifications"
  value       = aws_sns_topic.compliance_alerts.name
}

# Lambda Function Outputs
output "compliance_evaluator_function_name" {
  description = "Name of the compliance evaluator Lambda function"
  value       = aws_lambda_function.compliance_evaluator.function_name
}

output "compliance_evaluator_function_arn" {
  description = "ARN of the compliance evaluator Lambda function"
  value       = aws_lambda_function.compliance_evaluator.arn
}

output "auto_remediation_function_name" {
  description = "Name of the auto-remediation Lambda function"
  value       = var.enable_auto_remediation ? aws_lambda_function.auto_remediation[0].function_name : "Not created"
}

output "auto_remediation_function_arn" {
  description = "ARN of the auto-remediation Lambda function"
  value       = var.enable_auto_remediation ? aws_lambda_function.auto_remediation[0].arn : "Not created"
}

# AWS Config Outputs
output "config_bucket_name" {
  description = "Name of the S3 bucket used by AWS Config"
  value       = aws_s3_bucket.config_bucket.bucket
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket used by AWS Config"
  value       = aws_s3_bucket.config_bucket.arn
}

output "config_rule_name" {
  description = "Name of the AWS Config rule for VPC Lattice compliance"
  value       = aws_config_config_rule.vpc_lattice_compliance.name
}

output "config_rule_arn" {
  description = "ARN of the AWS Config rule for VPC Lattice compliance"
  value       = aws_config_config_rule.vpc_lattice_compliance.arn
}

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.compliance_recorder.name
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.compliance_delivery_channel.name
}

# IAM Role Outputs
output "config_service_role_arn" {
  description = "ARN of the AWS Config service role"
  value       = aws_iam_role.config_service_role.arn
}

output "lambda_compliance_role_arn" {
  description = "ARN of the Lambda compliance execution role"
  value       = aws_iam_role.lambda_compliance_role.arn
}

# Demo Resources Outputs (if created)
output "demo_vpc_id" {
  description = "ID of the demo VPC (if created)"
  value       = var.create_demo_resources ? aws_vpc.demo_vpc[0].id : "Not created"
}

output "demo_service_network_id" {
  description = "ID of the demo VPC Lattice service network (if created)"
  value       = var.create_demo_resources ? aws_vpclattice_service_network.demo_service_network[0].id : "Not created"
}

output "demo_service_network_name" {
  description = "Name of the demo VPC Lattice service network (if created)"
  value       = var.create_demo_resources ? aws_vpclattice_service_network.demo_service_network[0].name : "Not created"
}

output "demo_service_id" {
  description = "ID of the demo VPC Lattice service (if created)"
  value       = var.create_demo_resources ? aws_vpclattice_service.demo_service[0].id : "Not created"
}

output "demo_service_name" {
  description = "Name of the demo VPC Lattice service (if created)"
  value       = var.create_demo_resources ? aws_vpclattice_service.demo_service[0].name : "Not created"
}

# CloudWatch Logs Outputs
output "compliance_evaluator_log_group" {
  description = "CloudWatch log group for the compliance evaluator function"
  value       = aws_cloudwatch_log_group.compliance_evaluator_logs.name
}

output "auto_remediation_log_group" {
  description = "CloudWatch log group for the auto-remediation function"
  value       = var.enable_auto_remediation ? aws_cloudwatch_log_group.auto_remediation_logs[0].name : "Not created"
}

# Deployment Information
output "deployment_instructions" {
  description = "Instructions for verifying the deployment"
  value = <<-EOT
    VPC Lattice Policy Enforcement System Deployed Successfully!
    
    Key Components:
    - AWS Config Rule: ${aws_config_config_rule.vpc_lattice_compliance.name}
    - Compliance Evaluator: ${aws_lambda_function.compliance_evaluator.function_name}
    - Auto-Remediation: ${var.enable_auto_remediation ? aws_lambda_function.auto_remediation[0].function_name : "Disabled"}
    - SNS Topic: ${aws_sns_topic.compliance_alerts.name}
    
    Verification Steps:
    1. Confirm email subscription to SNS topic: ${aws_sns_topic.compliance_alerts.arn}
    2. Check AWS Config recorder status: aws configservice describe-configuration-recorder-status
    3. View compliance evaluations: aws configservice get-compliance-details-by-config-rule --config-rule-name ${aws_config_config_rule.vpc_lattice_compliance.name}
    
    Demo Resources Created: ${var.create_demo_resources ? "Yes" : "No"}
    ${var.create_demo_resources ? "- Non-compliant service network: ${aws_vpclattice_service_network.demo_service_network[0].name}" : ""}
    ${var.create_demo_resources ? "- Non-compliant service: ${aws_vpclattice_service.demo_service[0].name}" : ""}
    
    Monitor CloudWatch Logs:
    - Compliance Evaluator: ${aws_cloudwatch_log_group.compliance_evaluator_logs.name}
    ${var.enable_auto_remediation ? "- Auto-Remediation: ${aws_cloudwatch_log_group.auto_remediation_logs[0].name}" : ""}
  EOT
}

# Configuration Summary
output "compliance_policy_configuration" {
  description = "Summary of compliance policy configuration"
  value = {
    require_auth_policy   = var.require_auth_policy
    service_name_prefix   = var.service_name_prefix
    require_service_auth  = var.require_service_auth
    auto_remediation      = var.enable_auto_remediation
    notification_email    = var.notification_email
  }
}