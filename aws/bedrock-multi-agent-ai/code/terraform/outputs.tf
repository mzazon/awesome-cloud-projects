# Supervisor Agent Outputs
output "supervisor_agent_id" {
  description = "ID of the supervisor agent"
  value       = aws_bedrockagent_agent.supervisor.agent_id
}

output "supervisor_agent_arn" {
  description = "ARN of the supervisor agent"
  value       = aws_bedrockagent_agent.supervisor.agent_arn
}

output "supervisor_agent_alias_id" {
  description = "ID of the supervisor agent production alias"
  value       = aws_bedrockagent_agent_alias.supervisor_production.agent_alias_id
}

# Specialized Agents Outputs
output "finance_agent_id" {
  description = "ID of the financial analysis agent"
  value       = aws_bedrockagent_agent.finance.agent_id
}

output "support_agent_id" {
  description = "ID of the customer support agent"
  value       = aws_bedrockagent_agent.support.agent_id
}

output "analytics_agent_id" {
  description = "ID of the data analytics agent"
  value       = aws_bedrockagent_agent.analytics.agent_id
}

# Agent ARNs for external integration
output "agent_arns" {
  description = "Map of all agent ARNs"
  value = {
    supervisor = aws_bedrockagent_agent.supervisor.agent_arn
    finance    = aws_bedrockagent_agent.finance.agent_arn
    support    = aws_bedrockagent_agent.support.agent_arn
    analytics  = aws_bedrockagent_agent.analytics.agent_arn
  }
}

# EventBridge Outputs
output "eventbridge_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.multi_agent_bus.name
}

output "eventbridge_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.multi_agent_bus.arn
}

# Lambda Coordinator Outputs
output "coordinator_function_name" {
  description = "Name of the workflow coordinator Lambda function"
  value       = aws_lambda_function.workflow_coordinator.function_name
}

output "coordinator_function_arn" {
  description = "ARN of the workflow coordinator Lambda function"
  value       = aws_lambda_function.workflow_coordinator.arn
}

# DynamoDB Outputs
output "memory_table_name" {
  description = "Name of the agent memory DynamoDB table"
  value       = aws_dynamodb_table.agent_memory.name
}

output "memory_table_arn" {
  description = "ARN of the agent memory DynamoDB table"
  value       = aws_dynamodb_table.agent_memory.arn
}

output "memory_table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.agent_memory.stream_arn
}

# Dead Letter Queue Outputs
output "dlq_url" {
  description = "URL of the dead letter queue for failed events"
  value       = aws_sqs_queue.event_dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = aws_sqs_queue.event_dlq.arn
}

# IAM Role Outputs
output "bedrock_agent_role_arn" {
  description = "ARN of the Bedrock agent execution role"
  value       = aws_iam_role.bedrock_agent_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# Monitoring Outputs
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.multi_agent_dashboard.dashboard_name}"
}

output "log_groups" {
  description = "CloudWatch log groups for monitoring"
  value = {
    agents      = aws_cloudwatch_log_group.agent_logs.name
    coordinator = aws_cloudwatch_log_group.coordinator_logs.name
  }
}

# KMS Key Outputs (if encryption is enabled)
output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_resource_encryption ? aws_kms_key.multi_agent_key[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_resource_encryption ? aws_kms_key.multi_agent_key[0].key_id : null
}

# API Gateway Outputs (for external API access)
output "api_gateway_invoke_url" {
  description = "Invoke URL for the API Gateway"
  value       = aws_api_gateway_deployment.multi_agent_api.invoke_url
}

output "api_gateway_stage_name" {
  description = "Stage name for the API Gateway deployment"
  value       = aws_api_gateway_stage.api_stage.stage_name
}

# Resource Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    project_name      = var.project_name
    environment       = var.environment
    aws_region        = var.aws_region
    agents_deployed   = 4
    foundation_model  = var.foundation_model
    eventbridge_bus   = aws_cloudwatch_event_bus.multi_agent_bus.name
    memory_table      = aws_dynamodb_table.agent_memory.name
    coordinator       = aws_lambda_function.workflow_coordinator.function_name
    encryption_enabled = var.enable_resource_encryption
    monitoring_enabled = var.enable_enhanced_monitoring
  }
}

# Testing Endpoints
output "testing_commands" {
  description = "CLI commands for testing the multi-agent system"
  value = {
    invoke_supervisor_agent = "aws bedrock-agent-runtime invoke-agent --agent-id ${aws_bedrockagent_agent.supervisor.agent_id} --agent-alias-id ${aws_bedrockagent_agent_alias.supervisor_production.agent_alias_id} --session-id test-session-$(date +%s) --input-text 'Test multi-agent coordination'"
    send_test_event = "aws events put-events --entries '[{\"Source\":\"multi-agent.test\",\"DetailType\":\"Test Event\",\"Detail\":\"{\\\"test\\\":true}\",\"EventBusName\":\"${aws_cloudwatch_event_bus.multi_agent_bus.name}\"}]'"
    check_memory_table = "aws dynamodb scan --table-name ${aws_dynamodb_table.agent_memory.name} --limit 5"
    view_coordinator_logs = "aws logs tail /aws/lambda/${aws_lambda_function.workflow_coordinator.function_name} --since 5m"
  }
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs in USD (approximate)"
  value = {
    bedrock_agents = "~$50-200 (usage-based on invocations)"
    lambda_function = "~$5-20 (based on executions and duration)"
    dynamodb = "~$10-50 (based on read/write capacity and storage)"
    eventbridge = "~$1-10 (based on event volume)"
    cloudwatch = "~$5-25 (logs, metrics, and dashboard)"
    kms = "~$1/month per key if enabled"
    total_estimate = "~$70-300/month depending on usage patterns"
    note = "Costs vary significantly based on usage. Monitor AWS Cost Explorer for actual usage."
  }
}