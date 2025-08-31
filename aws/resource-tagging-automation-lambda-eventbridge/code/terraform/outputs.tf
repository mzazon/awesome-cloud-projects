# outputs.tf
# Output values for AWS resource tagging automation infrastructure

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for automated tagging"
  value       = aws_lambda_function.auto_tagger.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for automated tagging"
  value       = aws_lambda_function.auto_tagger.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.auto_tagger.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ============================================================================
# EventBridge Outputs
# ============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for resource creation events"
  value       = aws_cloudwatch_event_rule.resource_creation.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for resource creation events"
  value       = aws_cloudwatch_event_rule.resource_creation.arn
}

output "eventbridge_rule_state" {
  description = "Current state of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.resource_creation.state
}

# ============================================================================
# Resource Group Outputs
# ============================================================================

output "resource_group_name" {
  description = "Name of the Resource Group for auto-tagged resources"
  value       = var.enable_resource_group ? aws_resourcegroups_group.auto_tagged[0].name : null
}

output "resource_group_arn" {
  description = "ARN of the Resource Group for auto-tagged resources"
  value       = var.enable_resource_group ? aws_resourcegroups_group.auto_tagged[0].arn : null
}

# ============================================================================
# Monitoring Outputs
# ============================================================================

output "cloudwatch_alarm_lambda_errors" {
  description = "Name of the CloudWatch alarm for Lambda function errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "cloudwatch_alarm_lambda_duration" {
  description = "Name of the CloudWatch alarm for Lambda function duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name
}

output "dead_letter_queue_url" {
  description = "URL of the SQS dead letter queue for failed events"
  value       = aws_sqs_queue.dlq.url
}

output "dead_letter_queue_arn" {
  description = "ARN of the SQS dead letter queue for failed events"
  value       = aws_sqs_queue.dlq.arn
}

# ============================================================================
# Configuration Outputs
# ============================================================================

output "monitored_services" {
  description = "List of AWS services being monitored for resource creation"
  value       = var.aws_services
}

output "monitored_events" {
  description = "List of CloudTrail events being monitored for tagging"
  value       = var.cloudtrail_events
}

output "standard_tags" {
  description = "Standard tags applied to resources by the automation"
  value       = local.automated_tags
  sensitive   = false
}

output "project_configuration" {
  description = "Project configuration summary"
  value = {
    project_name         = var.project_name
    environment         = var.environment
    cost_center         = var.cost_center
    department          = var.department
    contact_email       = var.contact_email
    resource_suffix     = local.name_suffix
  }
}

# ============================================================================
# Usage Instructions
# ============================================================================

output "usage_instructions" {
  description = "Instructions for using the automated tagging system"
  value = {
    verification_commands = {
      check_lambda_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name}"
      list_tagged_resources = var.enable_resource_group ? "aws resource-groups list-group-resources --group-name ${aws_resourcegroups_group.auto_tagged[0].name}" : "Use Resource Groups Tagging API to find resources with AutoTagged=true"
      test_with_ec2 = "Create an EC2 instance and check if tags are automatically applied within 1-2 minutes"
    }
    monitoring = {
      lambda_metrics = "Monitor Lambda function invocations and errors in CloudWatch console"
      eventbridge_metrics = "Check EventBridge rule metrics for successful matches and invocations"
      cost_tracking = "Use AWS Cost Explorer with tag-based cost allocation for ${var.cost_center}"
    }
    customization = {
      modify_tags = "Update the standard_tags variable in variables.tf to change default tags"
      add_services = "Add more AWS services to aws_services and cloudtrail_events variables"
      extend_lambda = "Modify lambda_function.py.tpl to support additional resource types"
    }
  }
}

# ============================================================================
# Regional Information
# ============================================================================

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}