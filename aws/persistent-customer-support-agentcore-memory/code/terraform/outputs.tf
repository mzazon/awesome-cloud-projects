# ================================================================
# Outputs for Customer Support Agent Infrastructure
# Recipe: Persistent Customer Support Agent with Bedrock AgentCore Memory
# ================================================================

# ================================================================
# API GATEWAY OUTPUTS
# ================================================================

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint for customer support interactions"
  value       = "${aws_api_gateway_rest_api.support_api.execution_arn}/${aws_api_gateway_stage.support_api_stage.stage_name}"
}

output "api_gateway_invoke_url" {
  description = "Complete invoke URL for the customer support API"
  value       = "https://${aws_api_gateway_rest_api.support_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.support_api_stage.stage_name}/support"
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.support_api.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.support_api.arn
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.support_api_stage.stage_name
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.support_api.execution_arn
}

# ================================================================
# LAMBDA FUNCTION OUTPUTS
# ================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function handling customer support requests"
  value       = aws_lambda_function.support_agent.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.support_agent.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.support_agent.invoke_arn
}

output "lambda_function_role_arn" {
  description = "ARN of the IAM role for the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.support_agent.version
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# ================================================================
# BEDROCK AGENTCORE MEMORY OUTPUTS
# ================================================================

output "agentcore_memory_id" {
  description = "ID of the Bedrock AgentCore Memory for persistent context"
  value       = aws_bedrockagent_memory.customer_support_memory.id
  sensitive   = true
}

output "agentcore_memory_name" {
  description = "Name of the Bedrock AgentCore Memory"
  value       = aws_bedrockagent_memory.customer_support_memory.name
}

output "agentcore_memory_arn" {
  description = "ARN of the Bedrock AgentCore Memory"
  value       = aws_bedrockagent_memory.customer_support_memory.arn
}

# ================================================================
# DYNAMODB OUTPUTS
# ================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing customer data"
  value       = aws_dynamodb_table.customer_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.customer_data.arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.customer_data.id
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream (if enabled)"
  value       = aws_dynamodb_table.customer_data.stream_arn
}

# ================================================================
# CLOUDWATCH MONITORING OUTPUTS
# ================================================================

output "lambda_error_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_error_alarm.alarm_name
}

output "lambda_error_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_error_alarm.arn
}

output "api_gateway_4xx_alarm_name" {
  description = "Name of the CloudWatch alarm for API Gateway 4XX errors"
  value       = aws_cloudwatch_metric_alarm.api_gateway_4xx_alarm.alarm_name
}

output "api_gateway_4xx_alarm_arn" {
  description = "ARN of the CloudWatch alarm for API Gateway 4XX errors"
  value       = aws_cloudwatch_metric_alarm.api_gateway_4xx_alarm.arn
}

output "api_gateway_log_group_name" {
  description = "Name of the CloudWatch Log Group for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway_logs.name
}

output "api_gateway_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway_logs.arn
}

# ================================================================
# SQS DEAD LETTER QUEUE OUTPUTS
# ================================================================

output "lambda_dlq_name" {
  description = "Name of the SQS dead letter queue for Lambda function"
  value       = aws_sqs_queue.lambda_dlq.name
}

output "lambda_dlq_arn" {
  description = "ARN of the SQS dead letter queue for Lambda function"
  value       = aws_sqs_queue.lambda_dlq.arn
}

output "lambda_dlq_url" {
  description = "URL of the SQS dead letter queue for Lambda function"
  value       = aws_sqs_queue.lambda_dlq.url
}

# ================================================================
# SAMPLE DATA OUTPUTS
# ================================================================

output "sample_customer_ids" {
  description = "List of sample customer IDs created in DynamoDB"
  value       = var.create_sample_data ? ["customer-001", "customer-002"] : []
}

# ================================================================
# RESOURCE IDENTIFICATION OUTPUTS
# ================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

# ================================================================
# TESTING AND VALIDATION OUTPUTS
# ================================================================

output "test_curl_command" {
  description = "Example curl command to test the customer support API"
  value = <<-EOT
    curl -X POST ${aws_api_gateway_rest_api.support_api.execution_arn}/${aws_api_gateway_stage.support_api_stage.stage_name}/support \
      -H "Content-Type: application/json" \
      -d '{
        "customerId": "customer-001",
        "message": "Hi, I need help with my analytics dashboard. It'\''s loading very slowly.",
        "metadata": {
          "userAgent": "Mozilla/5.0 (Chrome)",
          "sessionLocation": "dashboard"
        }
      }'
  EOT
}

output "api_test_payload_example" {
  description = "Example JSON payload for testing the customer support API"
  value = jsonencode({
    customerId = "customer-001"
    message    = "Hi, I need assistance with my account setup. Can you help me configure my preferences?"
    metadata = {
      userAgent       = "Mozilla/5.0 (Chrome)"
      sessionLocation = "settings"
      timestamp       = "2024-01-01T12:00:00Z"
    }
  })
}

# ================================================================
# CONFIGURATION SUMMARY OUTPUTS
# ================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    api_gateway = {
      name        = aws_api_gateway_rest_api.support_api.name
      stage       = aws_api_gateway_stage.support_api_stage.stage_name
      url         = "https://${aws_api_gateway_rest_api.support_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.support_api_stage.stage_name}/support"
      description = "REST API endpoint for customer support interactions"
    }
    lambda_function = {
      name        = aws_lambda_function.support_agent.function_name
      runtime     = aws_lambda_function.support_agent.runtime
      memory_size = aws_lambda_function.support_agent.memory_size
      timeout     = aws_lambda_function.support_agent.timeout
      description = "Serverless function processing customer support requests"
    }
    agentcore_memory = {
      name        = aws_bedrockagent_memory.customer_support_memory.name
      description = "Persistent memory for maintaining customer conversation context"
    }
    dynamodb_table = {
      name         = aws_dynamodb_table.customer_data.name
      billing_mode = aws_dynamodb_table.customer_data.billing_mode
      description  = "Database storing customer metadata and preferences"
    }
    monitoring = {
      lambda_alarm     = aws_cloudwatch_metric_alarm.lambda_error_alarm.alarm_name
      api_gateway_alarm = aws_cloudwatch_metric_alarm.api_gateway_4xx_alarm.alarm_name
      description      = "CloudWatch alarms for monitoring system health"
    }
  }
}

# ================================================================
# SECURITY AND ACCESS OUTPUTS
# ================================================================

output "iam_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_environment_variables" {
  description = "Environment variables configured for the Lambda function"
  value = {
    MEMORY_ID         = aws_bedrockagent_memory.customer_support_memory.id
    DDB_TABLE_NAME    = aws_dynamodb_table.customer_data.name
    BEDROCK_MODEL_ID  = var.bedrock_model_id
  }
  sensitive = true
}

# ================================================================
# COST OPTIMIZATION OUTPUTS
# ================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed infrastructure"
  value = {
    api_gateway     = "~$3.50 per million requests + data transfer"
    lambda          = "~$0.20 per million requests + compute time"
    dynamodb        = "~$1.25 per million read/write request units"
    agentcore_memory = "Usage-based pricing for memory operations"
    bedrock         = "~$0.00025 per 1K input tokens, ~$0.00125 per 1K output tokens"
    cloudwatch      = "~$0.50 per month for logs and alarms"
    total_estimate  = "$10-50 per month for moderate usage"
  }
}

# ================================================================
# NEXT STEPS OUTPUTS
# ================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Test the API endpoint using the provided curl command",
    "Monitor CloudWatch logs for Lambda function execution",
    "Review and customize the Bedrock model responses",
    "Add authentication/authorization to the API Gateway",
    "Configure custom domain name for the API Gateway",
    "Set up additional monitoring and alerting as needed",
    "Scale DynamoDB capacity based on actual usage patterns",
    "Configure backup and recovery strategies",
    "Implement additional security controls (WAF, API keys)",
    "Add integration with your existing customer support tools"
  ]
}

# ================================================================
# DOCUMENTATION OUTPUTS
# ================================================================

output "documentation_links" {
  description = "Links to relevant AWS documentation"
  value = {
    bedrock_agentcore = "https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/"
    api_gateway      = "https://docs.aws.amazon.com/apigateway/latest/developerguide/"
    lambda           = "https://docs.aws.amazon.com/lambda/latest/dg/"
    dynamodb         = "https://docs.aws.amazon.com/dynamodb/latest/developerguide/"
    cloudwatch       = "https://docs.aws.amazon.com/cloudwatch/latest/monitoring/"
    bedrock          = "https://docs.aws.amazon.com/bedrock/latest/userguide/"
  }
}