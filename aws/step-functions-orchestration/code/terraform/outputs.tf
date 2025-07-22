# ===============================================================================
# Terraform Outputs for AWS Step Functions Microservices Orchestration
# ===============================================================================
# This file defines all outputs from the microservices orchestration
# infrastructure deployment for integration and verification purposes.
# ===============================================================================

# ===============================================================================
# Step Functions Outputs
# ===============================================================================

output "step_functions_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.microservices_workflow.arn
}

output "step_functions_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.microservices_workflow.name
}

output "step_functions_console_url" {
  description = "AWS Console URL for the Step Functions state machine"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.microservices_workflow.arn}"
}

output "step_functions_creation_date" {
  description = "Creation date of the Step Functions state machine"
  value       = aws_sfn_state_machine.microservices_workflow.creation_date
}

# ===============================================================================
# Lambda Functions Outputs
# ===============================================================================

output "lambda_functions" {
  description = "Map of Lambda function names to their ARNs"
  value = {
    user_service         = aws_lambda_function.user_service.arn
    order_service        = aws_lambda_function.order_service.arn
    payment_service      = aws_lambda_function.payment_service.arn
    inventory_service    = aws_lambda_function.inventory_service.arn
    notification_service = aws_lambda_function.notification_service.arn
  }
}

output "user_service_function_name" {
  description = "Name of the User Service Lambda function"
  value       = aws_lambda_function.user_service.function_name
}

output "user_service_function_arn" {
  description = "ARN of the User Service Lambda function"
  value       = aws_lambda_function.user_service.arn
}

output "order_service_function_name" {
  description = "Name of the Order Service Lambda function"
  value       = aws_lambda_function.order_service.function_name
}

output "order_service_function_arn" {
  description = "ARN of the Order Service Lambda function"
  value       = aws_lambda_function.order_service.arn
}

output "payment_service_function_name" {
  description = "Name of the Payment Service Lambda function"
  value       = aws_lambda_function.payment_service.function_name
}

output "payment_service_function_arn" {
  description = "ARN of the Payment Service Lambda function"
  value       = aws_lambda_function.payment_service.arn
}

output "inventory_service_function_name" {
  description = "Name of the Inventory Service Lambda function"
  value       = aws_lambda_function.inventory_service.function_name
}

output "inventory_service_function_arn" {
  description = "ARN of the Inventory Service Lambda function"
  value       = aws_lambda_function.inventory_service.arn
}

output "notification_service_function_name" {
  description = "Name of the Notification Service Lambda function"
  value       = aws_lambda_function.notification_service.function_name
}

output "notification_service_function_arn" {
  description = "ARN of the Notification Service Lambda function"
  value       = aws_lambda_function.notification_service.arn
}

# ===============================================================================
# EventBridge Outputs
# ===============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.microservices_trigger.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.microservices_trigger.arn
}

output "eventbridge_rule_event_pattern" {
  description = "Event pattern for the EventBridge rule"
  value       = aws_cloudwatch_event_rule.microservices_trigger.event_pattern
}

# ===============================================================================
# IAM Role Outputs
# ===============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "stepfunctions_execution_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_execution_role.arn
}

output "stepfunctions_execution_role_name" {
  description = "Name of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_execution_role.name
}

output "eventbridge_stepfunctions_role_arn" {
  description = "ARN of the EventBridge to Step Functions role"
  value       = aws_iam_role.eventbridge_stepfunctions_role.arn
}

output "eventbridge_stepfunctions_role_name" {
  description = "Name of the EventBridge to Step Functions role"
  value       = aws_iam_role.eventbridge_stepfunctions_role.name
}

# ===============================================================================
# CloudWatch Logs Outputs
# ===============================================================================

output "cloudwatch_log_groups" {
  description = "Map of service names to CloudWatch log group names"
  value = {
    user_service         = aws_cloudwatch_log_group.user_service_logs.name
    order_service        = aws_cloudwatch_log_group.order_service_logs.name
    payment_service      = aws_cloudwatch_log_group.payment_service_logs.name
    inventory_service    = aws_cloudwatch_log_group.inventory_service_logs.name
    notification_service = aws_cloudwatch_log_group.notification_service_logs.name
    step_functions       = aws_cloudwatch_log_group.stepfunctions_logs.name
  }
}

output "stepfunctions_log_group_arn" {
  description = "ARN of the Step Functions CloudWatch log group"
  value       = aws_cloudwatch_log_group.stepfunctions_logs.arn
}

output "stepfunctions_log_group_name" {
  description = "Name of the Step Functions CloudWatch log group"
  value       = aws_cloudwatch_log_group.stepfunctions_logs.name
}

# ===============================================================================
# Project Configuration Outputs
# ===============================================================================

output "project_name" {
  description = "Project name used for resource naming"
  value       = local.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ===============================================================================
# Testing and Validation Outputs
# ===============================================================================

output "test_event_sample" {
  description = "Sample event for testing the Step Functions workflow"
  value = jsonencode({
    userId = "test-user-12345"
    orderData = {
      items = [
        {
          productId = "PROD001"
          quantity  = 2
          price     = 29.99
        },
        {
          productId = "PROD002"
          quantity  = 1
          price     = 49.99
        }
      ]
    }
  })
}

output "eventbridge_test_command" {
  description = "AWS CLI command to test EventBridge integration"
  value = "aws events put-events --entries Source=microservices.orders,DetailType=\"Order Submitted\",Detail='{\"userId\":\"test-user-12345\",\"orderData\":{\"items\":[{\"productId\":\"PROD001\",\"quantity\":1,\"price\":99.99}]}}'"
}

output "stepfunctions_start_execution_command" {
  description = "AWS CLI command to start Step Functions execution manually"
  value = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.microservices_workflow.arn} --input '${jsonencode({
    userId = "test-user-12345"
    orderData = {
      items = [
        {
          productId = "PROD001"
          quantity  = 2
          price     = 29.99
        }
      ]
    }
  })}'"
}

# ===============================================================================
# Monitoring and Debugging Outputs
# ===============================================================================

output "cloudwatch_insights_queries" {
  description = "CloudWatch Insights queries for monitoring and debugging"
  value = {
    lambda_errors = "fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
    lambda_duration = "fields @timestamp, @duration | filter @type = \"REPORT\" | stats avg(@duration), max(@duration) by bin(5m)"
    stepfunctions_executions = "fields @timestamp, @message | filter @message like /execution/ | sort @timestamp desc | limit 20"
  }
}

output "monitoring_dashboard_widgets" {
  description = "Configuration for CloudWatch dashboard widgets"
  value = {
    lambda_duration_metrics = [
      aws_lambda_function.user_service.function_name,
      aws_lambda_function.order_service.function_name,
      aws_lambda_function.payment_service.function_name,
      aws_lambda_function.inventory_service.function_name,
      aws_lambda_function.notification_service.function_name
    ]
    stepfunctions_execution_metrics = aws_sfn_state_machine.microservices_workflow.name
  }
}

# ===============================================================================
# Resource Summary Outputs
# ===============================================================================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    lambda_functions     = 5
    step_functions      = 1
    eventbridge_rules   = 1
    iam_roles          = 3
    iam_policies       = 2
    cloudwatch_log_groups = 6
    total_resources    = 18
  }
}

output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    deployed_at = timestamp()
    terraform_workspace = terraform.workspace
    next_steps = [
      "1. Test individual Lambda functions using the AWS CLI or console",
      "2. Execute the Step Functions workflow with sample data",
      "3. Send test events through EventBridge to trigger the workflow",
      "4. Monitor execution logs in CloudWatch",
      "5. Set up CloudWatch alarms for production monitoring"
    ]
  }
}