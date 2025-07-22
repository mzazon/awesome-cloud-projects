# Output Values for Circuit Breaker Pattern Implementation
# These outputs provide essential information for testing and integration

#------------------------------------------------------------------------------
# Core Infrastructure Outputs
#------------------------------------------------------------------------------

output "state_machine_arn" {
  description = "ARN of the Circuit Breaker Step Functions state machine"
  value       = aws_sfn_state_machine.circuit_breaker.arn
}

output "state_machine_name" {
  description = "Name of the Circuit Breaker Step Functions state machine"
  value       = aws_sfn_state_machine.circuit_breaker.name
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing circuit breaker states"
  value       = aws_dynamodb_table.circuit_breaker_state.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table storing circuit breaker states"
  value       = aws_dynamodb_table.circuit_breaker_state.arn
}

#------------------------------------------------------------------------------
# Lambda Function Outputs
#------------------------------------------------------------------------------

output "downstream_service_function_name" {
  description = "Name of the downstream service Lambda function"
  value       = aws_lambda_function.downstream_service.function_name
}

output "downstream_service_function_arn" {
  description = "ARN of the downstream service Lambda function"
  value       = aws_lambda_function.downstream_service.arn
}

output "fallback_service_function_name" {
  description = "Name of the fallback service Lambda function"
  value       = aws_lambda_function.fallback_service.function_name
}

output "fallback_service_function_arn" {
  description = "ARN of the fallback service Lambda function"
  value       = aws_lambda_function.fallback_service.arn
}

output "health_check_function_name" {
  description = "Name of the health check Lambda function"
  value       = aws_lambda_function.health_check.function_name
}

output "health_check_function_arn" {
  description = "ARN of the health check Lambda function"
  value       = aws_lambda_function.health_check.arn
}

#------------------------------------------------------------------------------
# IAM Role Outputs
#------------------------------------------------------------------------------

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "step_functions_execution_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions_execution_role.arn
}

#------------------------------------------------------------------------------
# Monitoring Outputs
#------------------------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.step_functions_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.step_functions_logs.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for circuit breaker alerts (if created)"
  value       = var.enable_cloudwatch_alarms && var.sns_email_notification != "" ? aws_sns_topic.circuit_breaker_alerts[0].arn : null
}

#------------------------------------------------------------------------------
# Testing and Integration Outputs
#------------------------------------------------------------------------------

output "test_execution_command" {
  description = "AWS CLI command to test the circuit breaker state machine"
  value = <<-EOT
aws stepfunctions start-execution \
    --state-machine-arn ${aws_sfn_state_machine.circuit_breaker.arn} \
    --name "test-execution-$(date +%s)" \
    --input '{
        "service_name": "payment-service",
        "request_payload": {
            "amount": 100.00,
            "currency": "USD",
            "customer_id": "12345"
        }
    }'
EOT
}

output "circuit_breaker_state_check_command" {
  description = "AWS CLI command to check circuit breaker state in DynamoDB"
  value = <<-EOT
aws dynamodb get-item \
    --table-name ${aws_dynamodb_table.circuit_breaker_state.name} \
    --key '{"ServiceName": {"S": "payment-service"}}'
EOT
}

output "downstream_service_config_command" {
  description = "AWS CLI command to update downstream service configuration"
  value = <<-EOT
aws lambda update-function-configuration \
    --function-name ${aws_lambda_function.downstream_service.function_name} \
    --environment Variables='{
        "FAILURE_RATE": "0.9",
        "LATENCY_MS": "300"
    }'
EOT
}

#------------------------------------------------------------------------------
# Configuration Summary
#------------------------------------------------------------------------------

output "circuit_breaker_configuration" {
  description = "Circuit breaker configuration summary"
  value = {
    failure_threshold      = var.circuit_breaker_failure_threshold
    failure_rate          = var.downstream_service_failure_rate
    latency_ms           = var.downstream_service_latency_ms
    lambda_timeout       = var.lambda_timeout
    lambda_memory_size   = var.lambda_memory_size
    cloudwatch_alarms    = var.enable_cloudwatch_alarms
    notification_email   = var.sns_email_notification != "" ? "configured" : "not_configured"
  }
}

#------------------------------------------------------------------------------
# Resource Information
#------------------------------------------------------------------------------

output "resource_summary" {
  description = "Summary of created resources with their purposes"
  value = {
    state_machine = {
      name        = aws_sfn_state_machine.circuit_breaker.name
      arn         = aws_sfn_state_machine.circuit_breaker.arn
      purpose     = "Orchestrates circuit breaker logic and handles service routing"
    }
    dynamodb_table = {
      name        = aws_dynamodb_table.circuit_breaker_state.name
      arn         = aws_dynamodb_table.circuit_breaker_state.arn
      purpose     = "Stores circuit breaker state for each service"
    }
    lambda_functions = {
      downstream = {
        name    = aws_lambda_function.downstream_service.function_name
        arn     = aws_lambda_function.downstream_service.arn
        purpose = "Simulates external service with configurable failure rate"
      }
      fallback = {
        name    = aws_lambda_function.fallback_service.function_name
        arn     = aws_lambda_function.fallback_service.arn
        purpose = "Provides degraded response when circuit breaker is open"
      }
      health_check = {
        name    = aws_lambda_function.health_check.function_name
        arn     = aws_lambda_function.health_check.arn
        purpose = "Performs health checks and enables circuit breaker recovery"
      }
    }
  }
}

#------------------------------------------------------------------------------
# Validation Commands
#------------------------------------------------------------------------------

output "validation_commands" {
  description = "Commands to validate the circuit breaker implementation"
  value = {
    check_state_machine = "aws stepfunctions describe-state-machine --state-machine-arn ${aws_sfn_state_machine.circuit_breaker.arn}"
    check_lambda_functions = [
      "aws lambda get-function --function-name ${aws_lambda_function.downstream_service.function_name}",
      "aws lambda get-function --function-name ${aws_lambda_function.fallback_service.function_name}",
      "aws lambda get-function --function-name ${aws_lambda_function.health_check.function_name}"
    ]
    check_dynamodb_table = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.circuit_breaker_state.name}"
    view_logs = "aws logs describe-log-groups --log-group-name-prefix ${aws_cloudwatch_log_group.step_functions_logs.name}"
  }
}

#------------------------------------------------------------------------------
# Cleanup Commands
#------------------------------------------------------------------------------

output "cleanup_verification" {
  description = "Commands to verify resource cleanup"
  value = {
    verify_state_machine_deleted = "aws stepfunctions list-state-machines --query 'stateMachines[?name==`${aws_sfn_state_machine.circuit_breaker.name}`]'"
    verify_lambda_functions_deleted = [
      "aws lambda list-functions --query 'Functions[?FunctionName==`${aws_lambda_function.downstream_service.function_name}`]'",
      "aws lambda list-functions --query 'Functions[?FunctionName==`${aws_lambda_function.fallback_service.function_name}`]'",
      "aws lambda list-functions --query 'Functions[?FunctionName==`${aws_lambda_function.health_check.function_name}`]'"
    ]
    verify_dynamodb_table_deleted = "aws dynamodb list-tables --query 'TableNames[?@==`${aws_dynamodb_table.circuit_breaker_state.name}`]'"
  }
}