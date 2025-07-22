# ================================
# Core Infrastructure Outputs
# ================================

output "resource_prefix" {
  description = "Prefix used for all resource names"
  value       = local.resource_prefix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ================================
# Step Functions Outputs
# ================================

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine for business process automation"
  value       = aws_sfn_state_machine.business_workflow.arn
}

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.business_workflow.name
}

output "step_functions_console_url" {
  description = "AWS Console URL for the Step Functions state machine"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.business_workflow.arn}"
}

output "step_functions_execution_command" {
  description = "AWS CLI command to start a Step Functions execution"
  value = <<-EOT
aws stepfunctions start-execution \
  --state-machine-arn ${aws_sfn_state_machine.business_workflow.arn} \
  --name "test-execution-$(date +%s)" \
  --input '{"processData":{"processId":"BP-001","type":"expense-approval","amount":5000,"requestor":"user@example.com","description":"Software licensing renewal","processingTime":1}}'
EOT
}

# ================================
# Lambda Function Outputs
# ================================

output "lambda_function_arn" {
  description = "ARN of the business processor Lambda function"
  value       = aws_lambda_function.business_processor.arn
}

output "lambda_function_name" {
  description = "Name of the business processor Lambda function"
  value       = aws_lambda_function.business_processor.function_name
}

output "approval_lambda_function_arn" {
  description = "ARN of the approval handler Lambda function"
  value       = aws_lambda_function.approval_handler.arn
}

output "approval_lambda_function_name" {
  description = "Name of the approval handler Lambda function"
  value       = aws_lambda_function.approval_handler.function_name
}

# ================================
# SQS Queue Outputs
# ================================

output "sqs_queue_url" {
  description = "URL of the SQS queue for task management and audit logging"
  value       = aws_sqs_queue.task_queue.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for task management"
  value       = aws_sqs_queue.task_queue.arn
}

output "sqs_queue_name" {
  description = "Name of the SQS queue"
  value       = aws_sqs_queue.task_queue.name
}

output "sqs_receive_messages_command" {
  description = "AWS CLI command to receive messages from the SQS queue"
  value       = "aws sqs receive-message --queue-url ${aws_sqs_queue.task_queue.url} --max-number-of-messages 10"
}

# ================================
# SNS Topic Outputs
# ================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for process notifications"
  value       = aws_sns_topic.notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.notifications.name
}

output "sns_subscription_status" {
  description = "Status of email subscription (if configured)"
  value       = var.notification_email != "" ? "Email subscription created for ${var.notification_email}" : "No email subscription configured"
}

# ================================
# API Gateway Outputs
# ================================

output "api_gateway_id" {
  description = "ID of the API Gateway REST API for human approvals"
  value       = aws_api_gateway_rest_api.approval_api.id
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway for human approval callbacks"
  value       = "https://${aws_api_gateway_rest_api.approval_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "approval_endpoint_url" {
  description = "Complete URL for the approval endpoint"
  value       = "https://${aws_api_gateway_rest_api.approval_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/approval"
}

output "approval_api_usage_example" {
  description = "Example curl command for approving a process via API"
  value = <<-EOT
curl -X POST ${aws_api_gateway_rest_api.approval_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/approval \
  -H "Content-Type: application/json" \
  -d '{"taskToken":"TASK_TOKEN_FROM_SNS_MESSAGE","decision":"APPROVE","approver":"manager@company.com","comments":"Approved for processing"}'
EOT
}

# ================================
# Monitoring Outputs
# ================================

output "cloudwatch_log_groups" {
  description = "CloudWatch Log Groups created for monitoring"
  value = {
    step_functions = aws_cloudwatch_log_group.step_functions_logs.name
    lambda_processor = aws_cloudwatch_log_group.lambda_logs.name
    lambda_approval = aws_cloudwatch_log_group.approval_lambda_logs.name
  }
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring"
  value = {
    step_functions_failures = aws_cloudwatch_metric_alarm.step_functions_failures.alarm_name
    lambda_errors = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
  }
}

# ================================
# IAM Role Outputs
# ================================

output "step_functions_role_arn" {
  description = "ARN of the IAM role used by Step Functions"
  value       = aws_iam_role.step_functions_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the business processor Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "approval_lambda_role_arn" {
  description = "ARN of the IAM role used by the approval handler Lambda function"
  value       = aws_iam_role.approval_lambda_role.arn
}

# ================================
# Testing and Validation Outputs
# ================================

output "test_workflow_command" {
  description = "Complete command to test the business process workflow"
  value = <<-EOT
# Create test input file
echo '{"processData":{"processId":"BP-$(date +%s)","type":"expense-approval","amount":5000,"requestor":"user@example.com","description":"Software licensing renewal","processingTime":1}}' > test-input.json

# Start workflow execution
aws stepfunctions start-execution \
  --state-machine-arn ${aws_sfn_state_machine.business_workflow.arn} \
  --name "test-execution-$(date +%s)" \
  --input file://test-input.json

# Monitor execution (get the execution ARN from the previous command output)
# aws stepfunctions describe-execution --execution-arn EXECUTION_ARN
EOT
}

output "monitoring_commands" {
  description = "Commands for monitoring the business process automation"
  value = {
    list_executions = "aws stepfunctions list-executions --state-machine-arn ${aws_sfn_state_machine.business_workflow.arn}"
    check_sqs_messages = "aws sqs receive-message --queue-url ${aws_sqs_queue.task_queue.url}"
    view_lambda_logs = "aws logs tail /aws/lambda/${aws_lambda_function.business_processor.function_name} --follow"
    view_stepfunctions_logs = "aws logs tail /aws/stepfunctions/${local.resource_prefix}-workflow --follow"
  }
}

# ================================
# Configuration Summary
# ================================

output "deployment_summary" {
  description = "Summary of the deployed business process automation infrastructure"
  value = {
    project_name = var.project_name
    environment = var.environment
    resource_prefix = local.resource_prefix
    region = data.aws_region.current.name
    step_functions_state_machine = aws_sfn_state_machine.business_workflow.name
    lambda_functions = {
      business_processor = aws_lambda_function.business_processor.function_name
      approval_handler = aws_lambda_function.approval_handler.function_name
    }
    notification_endpoints = {
      sns_topic = aws_sns_topic.notifications.name
      sqs_queue = aws_sqs_queue.task_queue.name
      api_gateway = aws_api_gateway_rest_api.approval_api.name
    }
    monitoring = {
      log_retention_days = 14
      alarms_configured = 2
      detailed_monitoring = var.enable_detailed_monitoring
    }
  }
}

# ================================
# Security Information
# ================================

output "security_considerations" {
  description = "Important security information for the deployment"
  value = {
    iam_roles_created = 3
    encryption_enabled = {
      sns_topic = "AWS managed KMS key"
      sqs_queue = "SQS managed encryption"
      lambda_environment = "Default encryption"
    }
    network_security = {
      api_gateway_type = "Regional"
      lambda_vpc = "Not configured (uses AWS managed VPC)"
    }
    access_patterns = {
      step_functions = "IAM role-based access to Lambda, SNS, and SQS"
      lambda = "Execution role with minimal required permissions"
      api_gateway = "Public endpoint (consider adding API keys or authentication for production)"
    }
  }
}

# ================================
# Next Steps and Recommendations
# ================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure email subscription to SNS topic: aws sns subscribe --topic-arn ${aws_sns_topic.notifications.arn} --protocol email --notification-endpoint your-email@company.com",
    "2. Test the workflow using the provided test command above",
    "3. Set up CloudWatch dashboards for business process monitoring",
    "4. Consider implementing API Gateway authentication for production use",
    "5. Review and adjust timeout settings based on your business process requirements",
    "6. Implement additional business logic in the Lambda function as needed",
    "7. Consider setting up VPC configuration for Lambda functions if required by security policies"
  ]
}