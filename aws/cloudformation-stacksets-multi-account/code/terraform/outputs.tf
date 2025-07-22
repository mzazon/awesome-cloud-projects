# Core infrastructure outputs
output "management_account_id" {
  description = "AWS account ID of the management account"
  value       = data.aws_caller_identity.current.account_id
}

output "organization_id" {
  description = "AWS Organizations ID"
  value       = local.organization_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# S3 bucket outputs
output "template_bucket_name" {
  description = "Name of the S3 bucket containing CloudFormation templates"
  value       = aws_s3_bucket.templates.bucket
}

output "template_bucket_arn" {
  description = "ARN of the S3 bucket containing CloudFormation templates"
  value       = aws_s3_bucket.templates.arn
}

output "template_bucket_domain_name" {
  description = "Domain name of the S3 bucket containing CloudFormation templates"
  value       = aws_s3_bucket.templates.bucket_domain_name
}

# IAM role outputs
output "stackset_administrator_role_arn" {
  description = "ARN of the StackSet administrator role"
  value       = aws_iam_role.stackset_administrator.arn
}

output "stackset_administrator_role_name" {
  description = "Name of the StackSet administrator role"
  value       = aws_iam_role.stackset_administrator.name
}

output "stackset_administrator_policy_arn" {
  description = "ARN of the StackSet administrator policy"
  value       = aws_iam_policy.stackset_administrator.arn
}

# StackSet outputs
output "execution_roles_stackset_name" {
  description = "Name of the execution roles StackSet"
  value       = aws_cloudformation_stack_set.execution_roles.name
}

output "execution_roles_stackset_arn" {
  description = "ARN of the execution roles StackSet"
  value       = aws_cloudformation_stack_set.execution_roles.arn
}

output "execution_roles_stackset_id" {
  description = "ID of the execution roles StackSet"
  value       = aws_cloudformation_stack_set.execution_roles.stack_set_id
}

output "governance_stackset_name" {
  description = "Name of the governance StackSet"
  value       = aws_cloudformation_stack_set.governance.name
}

output "governance_stackset_arn" {
  description = "ARN of the governance StackSet"
  value       = aws_cloudformation_stack_set.governance.arn
}

output "governance_stackset_id" {
  description = "ID of the governance StackSet"
  value       = aws_cloudformation_stack_set.governance.stack_set_id
}

# Target deployment outputs
output "target_accounts" {
  description = "List of target AWS account IDs for StackSet deployment"
  value       = local.target_accounts
}

output "target_organizational_units" {
  description = "List of organizational unit IDs for StackSet deployment"
  value       = local.target_ou_ids
}

output "target_regions" {
  description = "List of target AWS regions for multi-region deployment"
  value       = var.target_regions
}

# Template outputs
output "execution_role_template_url" {
  description = "URL of the execution role CloudFormation template"
  value       = "https://${aws_s3_bucket.templates.bucket}.s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_object.execution_role_template.key}"
}

output "governance_template_url" {
  description = "URL of the governance CloudFormation template"
  value       = "https://${aws_s3_bucket.templates.bucket}.s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_object.governance_template.key}"
}

# Monitoring outputs (conditional)
output "stackset_alerts_topic_arn" {
  description = "ARN of the SNS topic for StackSet alerts"
  value       = var.enable_monitoring ? aws_sns_topic.stackset_alerts[0].arn : null
}

output "stackset_operations_log_group_name" {
  description = "Name of the CloudWatch log group for StackSet operations"
  value       = var.enable_monitoring ? aws_cloudwatch_log_group.stackset_operations[0].name : null
}

output "drift_detection_lambda_function_name" {
  description = "Name of the Lambda function for drift detection"
  value       = var.enable_monitoring ? aws_lambda_function.drift_detection[0].function_name : null
}

output "drift_detection_lambda_arn" {
  description = "ARN of the Lambda function for drift detection"
  value       = var.enable_monitoring ? aws_lambda_function.drift_detection[0].arn : null
}

output "drift_detection_schedule_rule_name" {
  description = "Name of the CloudWatch Event rule for drift detection schedule"
  value       = var.enable_monitoring ? aws_cloudwatch_event_rule.drift_detection_schedule[0].name : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for StackSet monitoring"
  value       = var.enable_monitoring ? aws_cloudwatch_dashboard.stackset_monitoring[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for StackSet monitoring"
  value       = var.enable_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.stackset_monitoring[0].dashboard_name}" : null
}

# Configuration outputs
output "compliance_level" {
  description = "Compliance level configured for governance policies"
  value       = var.compliance_level
}

output "auto_deployment_enabled" {
  description = "Whether auto-deployment is enabled for new accounts"
  value       = var.enable_auto_deployment
}

output "retain_stacks_on_account_removal" {
  description = "Whether stacks are retained when accounts are removed from OUs"
  value       = var.retain_stacks_on_account_removal
}

# Operation preferences outputs
output "operation_preferences" {
  description = "StackSet operation preferences configuration"
  value = {
    region_concurrency_type      = var.operation_preferences.region_concurrency_type
    max_concurrent_percentage    = var.operation_preferences.max_concurrent_percentage
    failure_tolerance_percentage = var.operation_preferences.failure_tolerance_percentage
  }
}

# Stack instance outputs
output "execution_roles_stack_instances" {
  description = "Information about execution roles stack instances"
  value = length(local.target_accounts) > 0 ? {
    accounts = local.target_accounts
    regions  = [data.aws_region.current.name]
  } : null
}

output "governance_stack_instances_ou" {
  description = "Information about governance stack instances deployed to organizational units"
  value = length(local.target_ou_ids) > 0 ? {
    organizational_units = local.target_ou_ids
    regions             = var.target_regions
  } : null
}

output "governance_stack_instances_accounts" {
  description = "Information about governance stack instances deployed to specific accounts"
  value = length(local.target_accounts) > 0 && length(local.target_ou_ids) == 0 ? {
    accounts = local.target_accounts
    regions  = var.target_regions
  } : null
}

# Useful commands for validation
output "validation_commands" {
  description = "Useful AWS CLI commands for validating the StackSet deployment"
  value = {
    list_stack_sets = "aws cloudformation list-stack-sets --region ${data.aws_region.current.name}"
    describe_governance_stackset = "aws cloudformation describe-stack-set --stack-set-name ${local.stackset_name} --region ${data.aws_region.current.name}"
    list_governance_instances = "aws cloudformation list-stack-instances --stack-set-name ${local.stackset_name} --region ${data.aws_region.current.name}"
    list_stackset_operations = "aws cloudformation list-stack-set-operations --stack-set-name ${local.stackset_name} --region ${data.aws_region.current.name}"
    detect_drift = "aws cloudformation detect-stack-set-drift --stack-set-name ${local.stackset_name} --region ${data.aws_region.current.name}"
  }
}

# Cleanup commands
output "cleanup_commands" {
  description = "AWS CLI commands for cleaning up the StackSet deployment"
  value = {
    delete_governance_instances = "aws cloudformation delete-stack-instances --stack-set-name ${local.stackset_name} --accounts ${join(",", local.target_accounts)} --regions ${join(",", var.target_regions)} --retain-stacks false --region ${data.aws_region.current.name}"
    delete_governance_stackset = "aws cloudformation delete-stack-set --stack-set-name ${local.stackset_name} --region ${data.aws_region.current.name}"
    delete_execution_instances = "aws cloudformation delete-stack-instances --stack-set-name ${local.execution_role_stackset_name} --accounts ${join(",", local.target_accounts)} --regions ${data.aws_region.current.name} --retain-stacks false --region ${data.aws_region.current.name}"
    delete_execution_stackset = "aws cloudformation delete-stack-set --stack-set-name ${local.execution_role_stackset_name} --region ${data.aws_region.current.name}"
  }
}

# Security and compliance outputs
output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    password_policy_enforced = true
    cloudtrail_enabled = true
    guardduty_enabled = var.guardduty_config.enable
    config_enabled = var.config_configuration.enable_all_supported
    s3_encryption_enabled = true
    s3_public_access_blocked = true
    multi_region_deployment = length(var.target_regions) > 1
    drift_detection_enabled = var.enable_monitoring
  }
}

# Cost optimization information
output "cost_optimization_notes" {
  description = "Notes on cost optimization for the StackSet deployment"
  value = {
    s3_lifecycle_enabled = var.s3_bucket_configuration.lifecycle_enabled
    log_retention_days = var.lambda_config.log_retention
    estimated_monthly_cost = "Varies based on number of accounts and regions. Main costs: CloudTrail logging, Config recording, GuardDuty findings, Lambda execution, S3 storage."
    cost_optimization_tips = [
      "Use S3 lifecycle policies to transition logs to cheaper storage classes",
      "Adjust log retention periods based on compliance requirements",
      "Monitor GuardDuty findings volume to optimize costs",
      "Consider using CloudFormation StackSets auto-deployment to reduce operational overhead"
    ]
  }
}