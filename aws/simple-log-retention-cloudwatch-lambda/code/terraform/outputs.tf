# Lambda function outputs
output "lambda_function_arn" {
  description = "ARN of the log retention management Lambda function"
  value       = aws_lambda_function.log_retention_manager.arn
}

output "lambda_function_name" {
  description = "Name of the log retention management Lambda function"
  value       = aws_lambda_function.log_retention_manager.function_name
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.log_retention_manager.version
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.log_retention_manager.last_modified
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.log_retention_manager.invoke_arn
}

# IAM role outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.name
}

# EventBridge outputs
output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule (if enabled)"
  value       = var.schedule_enabled ? aws_cloudwatch_event_rule.log_retention_schedule[0].arn : null
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule (if enabled)"
  value       = var.schedule_enabled ? aws_cloudwatch_event_rule.log_retention_schedule[0].name : null
}

output "schedule_expression" {
  description = "EventBridge schedule expression used"
  value       = var.schedule_expression
}

# CloudWatch Log Group outputs
output "lambda_log_group_name" {
  description = "Name of the Lambda function's CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda function's CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# Test log groups outputs (if created)
output "test_log_groups" {
  description = "Names of created test log groups"
  value       = var.create_test_log_groups ? [for lg in aws_cloudwatch_log_group.test_log_groups : lg.name] : []
}

# Configuration outputs
output "default_retention_days" {
  description = "Default retention period configured for unmatched log groups"
  value       = var.default_retention_days
}

output "retention_rules" {
  description = "Log group pattern to retention days mapping"
  value       = var.retention_rules
}

# Resource naming outputs
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

# Deployment summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    lambda_function = {
      name    = aws_lambda_function.log_retention_manager.function_name
      arn     = aws_lambda_function.log_retention_manager.arn
      runtime = aws_lambda_function.log_retention_manager.runtime
      timeout = aws_lambda_function.log_retention_manager.timeout
      memory  = aws_lambda_function.log_retention_manager.memory_size
    }
    iam_role = {
      name = aws_iam_role.lambda_execution_role.name
      arn  = aws_iam_role.lambda_execution_role.arn
    }
    eventbridge_rule = var.schedule_enabled ? {
      name                = aws_cloudwatch_event_rule.log_retention_schedule[0].name
      arn                 = aws_cloudwatch_event_rule.log_retention_schedule[0].arn
      schedule_expression = aws_cloudwatch_event_rule.log_retention_schedule[0].schedule_expression
      state              = aws_cloudwatch_event_rule.log_retention_schedule[0].state
    } : null
    configuration = {
      default_retention_days = var.default_retention_days
      retention_rules       = var.retention_rules
      schedule_enabled      = var.schedule_enabled
    }
  }
}

# Manual invocation command
output "manual_invocation_command" {
  description = "AWS CLI command to manually invoke the Lambda function"
  value = "aws lambda invoke --function-name ${aws_lambda_function.log_retention_manager.function_name} --payload '{}' --cli-binary-format raw-in-base64-out response.json"
}

# Test command
output "test_log_groups_command" {
  description = "AWS CLI command to check retention policies on test log groups"
  value = var.create_test_log_groups ? "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/test-function-${local.resource_suffix}' --query 'logGroups[*].{Name:logGroupName,Retention:retentionInDays}'" : "Test log groups not created. Set create_test_log_groups=true to create them."
}