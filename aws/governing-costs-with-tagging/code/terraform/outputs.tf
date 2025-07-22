# ============================================================================
# Core Infrastructure Outputs
# ============================================================================

output "project_name" {
  description = "Name of the cost management tagging project"
  value       = var.project_name
}

output "environment" {
  description = "Environment for the tagging strategy implementation"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where the infrastructure is deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where the infrastructure is deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# SNS Topic Outputs
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for tag compliance notifications"
  value       = aws_sns_topic.tag_compliance.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for tag compliance notifications"
  value       = aws_sns_topic.tag_compliance.name
}

output "notification_email" {
  description = "Email address configured for tag compliance notifications"
  value       = var.notification_email
  sensitive   = true
}

# ============================================================================
# AWS Config Outputs
# ============================================================================

output "config_bucket_name" {
  description = "Name of the S3 bucket used for AWS Config"
  value       = aws_s3_bucket.config_bucket.id
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket used for AWS Config"
  value       = aws_s3_bucket.config_bucket.arn
}

output "config_role_arn" {
  description = "ARN of the IAM role used by AWS Config"
  value       = aws_iam_role.config_role.arn
}

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.main.name
}

output "config_recorder_status" {
  description = "Status of the AWS Config configuration recorder"
  value       = var.enable_config_recorder ? "enabled" : "disabled"
}

# ============================================================================
# AWS Config Rules Outputs
# ============================================================================

output "config_rules" {
  description = "List of AWS Config rules created for tag compliance"
  value = {
    costcenter_rule = {
      name = aws_config_config_rule.required_tag_costcenter.name
      arn  = aws_config_config_rule.required_tag_costcenter.arn
    }
    environment_rule = {
      name = aws_config_config_rule.required_tag_environment.name
      arn  = aws_config_config_rule.required_tag_environment.arn
    }
    project_rule = {
      name = aws_config_config_rule.required_tag_project.name
      arn  = aws_config_config_rule.required_tag_project.arn
    }
    owner_rule = {
      name = aws_config_config_rule.required_tag_owner.name
      arn  = aws_config_config_rule.required_tag_owner.arn
    }
  }
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for tag remediation"
  value       = aws_lambda_function.tag_remediation.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for tag remediation"
  value       = aws_lambda_function.tag_remediation.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_log_group" {
  description = "CloudWatch log group for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ============================================================================
# Resource Groups Outputs
# ============================================================================

output "resource_groups" {
  description = "Resource groups created for tag-based organization"
  value = {
    production_environment = {
      name = aws_resourcegroups_group.production_environment.name
      arn  = aws_resourcegroups_group.production_environment.arn
    }
    engineering_costcenter = {
      name = aws_resourcegroups_group.engineering_costcenter.name
      arn  = aws_resourcegroups_group.engineering_costcenter.arn
    }
  }
}

# ============================================================================
# Demo Resources Outputs
# ============================================================================

output "demo_instance_id" {
  description = "ID of the demo EC2 instance (if created)"
  value       = var.create_demo_resources ? aws_instance.demo_instance[0].id : null
}

output "demo_instance_tags" {
  description = "Tags applied to the demo EC2 instance (if created)"
  value       = var.create_demo_resources ? aws_instance.demo_instance[0].tags : null
}

output "demo_bucket_name" {
  description = "Name of the demo S3 bucket (if created)"
  value       = var.create_demo_resources ? aws_s3_bucket.demo_bucket[0].id : null
}

output "demo_bucket_arn" {
  description = "ARN of the demo S3 bucket (if created)"
  value       = var.create_demo_resources ? aws_s3_bucket.demo_bucket[0].arn : null
}

# ============================================================================
# Tag Taxonomy Outputs
# ============================================================================

output "tag_taxonomy" {
  description = "Complete tag taxonomy configuration for reference"
  value       = local.tag_taxonomy
}

output "cost_allocation_tags" {
  description = "List of tags configured for cost allocation"
  value       = var.cost_allocation_tags
}

output "allowed_cost_centers" {
  description = "List of allowed cost centers for tag validation"
  value       = var.allowed_cost_centers
}

output "allowed_environments" {
  description = "List of allowed environments for tag validation"
  value       = var.allowed_environments
}

output "allowed_applications" {
  description = "List of allowed application types for tag validation"
  value       = var.allowed_applications
}

# ============================================================================
# Operational Outputs
# ============================================================================

output "tag_taxonomy_file" {
  description = "Path to the local tag taxonomy documentation file"
  value       = local_file.tag_taxonomy.filename
}

output "deployment_summary" {
  description = "Summary of deployed infrastructure components"
  value = {
    sns_notifications = "Configured for ${var.notification_email}"
    config_rules      = "4 rules for required tag validation"
    lambda_function   = "Automated remediation enabled"
    resource_groups   = "2 groups for cost allocation"
    demo_resources    = var.create_demo_resources ? "Created for testing" : "Disabled"
    config_recorder   = var.enable_config_recorder ? "Active" : "Inactive"
  }
}

# ============================================================================
# Next Steps Outputs
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm SNS subscription by checking email: ${var.notification_email}",
    "2. Activate cost allocation tags in AWS Billing Console",
    "3. Wait 24 hours for cost allocation tags to appear in Cost Explorer",
    "4. Create sample resources to test tag compliance detection",
    "5. Review AWS Config compliance dashboard for tag violations",
    "6. Update tag taxonomy file as organizational needs evolve",
    "7. Train teams on proper resource tagging practices"
  ]
}

output "cost_explorer_guidance" {
  description = "Instructions for Cost Explorer configuration"
  value = {
    activation_required = "Cost allocation tags must be manually activated in AWS Billing Console"
    tags_to_activate   = var.cost_allocation_tags
    console_url        = "https://console.aws.amazon.com/billing/home#/tags"
    reporting_delay    = "24 hours after activation for tags to appear in reports"
  }
}

output "monitoring_resources" {
  description = "Resources to monitor for the tagging strategy"
  value = {
    config_compliance = "Monitor Config rule compliance in AWS Config console"
    lambda_logs      = "Review Lambda function logs: ${aws_cloudwatch_log_group.lambda_logs.name}"
    sns_deliveries   = "Check SNS topic metrics: ${aws_sns_topic.tag_compliance.name}"
    resource_groups  = "Use Resource Groups to view tagged resources by category"
  }
}