# Managed Blockchain Outputs
output "ethereum_node_id" {
  description = "ID of the Ethereum node"
  value       = aws_managedblockchain_node.ethereum_node.id
}

output "ethereum_node_status" {
  description = "Status of the Ethereum node"
  value       = aws_managedblockchain_node.ethereum_node.status
}

output "ethereum_node_http_endpoint" {
  description = "HTTP endpoint for the Ethereum node"
  value       = aws_managedblockchain_node.ethereum_node.http_endpoint
  sensitive   = true
}

output "ethereum_node_websocket_endpoint" {
  description = "WebSocket endpoint for the Ethereum node"
  value       = aws_managedblockchain_node.ethereum_node.websocket_endpoint
  sensitive   = true
}

output "ethereum_network" {
  description = "Ethereum network the node is connected to"
  value       = var.ethereum_network
}

# S3 Bucket Outputs
output "contract_artifacts_bucket_name" {
  description = "Name of the S3 bucket storing contract artifacts"
  value       = aws_s3_bucket.contract_artifacts.bucket
}

output "contract_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket storing contract artifacts"
  value       = aws_s3_bucket.contract_artifacts.arn
}

output "contract_artifacts_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.contract_artifacts.bucket_domain_name
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for contract management"
  value       = aws_lambda_function.contract_manager.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for contract management"
  value       = aws_lambda_function.contract_manager.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.contract_manager.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.contract_manager.version
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.contract_manager.last_modified
}

# API Gateway Outputs
output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.ethereum_api.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.ethereum_api.name
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.ethereum_api.execution_arn
}

output "api_gateway_invoke_url" {
  description = "Invoke URL of the API Gateway stage"
  value       = aws_api_gateway_stage.ethereum_stage.invoke_url
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.ethereum_stage.stage_name
}

output "ethereum_api_endpoint" {
  description = "Full URL for the Ethereum API endpoint"
  value       = "${aws_api_gateway_stage.ethereum_stage.invoke_url}/ethereum"
}

# IAM Role Outputs
output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_blockchain_policy_arn" {
  description = "ARN of the blockchain access policy"
  value       = aws_iam_policy.lambda_blockchain_policy.arn
}

# Systems Manager Parameter Outputs
output "ssm_parameter_http_endpoint" {
  description = "Name of the SSM parameter storing HTTP endpoint"
  value       = aws_ssm_parameter.node_http_endpoint.name
}

output "ssm_parameter_ws_endpoint" {
  description = "Name of the SSM parameter storing WebSocket endpoint"
  value       = aws_ssm_parameter.node_ws_endpoint.name
}

# CloudWatch Outputs
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "api_gateway_log_group_name" {
  description = "Name of the CloudWatch log group for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway_logs.name
}

output "api_gateway_log_group_arn" {
  description = "ARN of the CloudWatch log group for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway_logs.arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (if enabled)"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.ethereum_dashboard[0].dashboard_name : null
}

output "lambda_error_alarm_name" {
  description = "Name of the Lambda error CloudWatch alarm (if enabled)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "api_gateway_error_alarm_name" {
  description = "Name of the API Gateway error CloudWatch alarm (if enabled)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.api_gateway_errors[0].alarm_name : null
}

# Random Suffix Output
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# Configuration Outputs
output "blockchain_node_instance_type" {
  description = "Instance type of the blockchain node"
  value       = var.blockchain_node_instance_type
}

output "blockchain_node_availability_zone" {
  description = "Availability zone of the blockchain node"
  value       = local.blockchain_az
}

output "lambda_runtime" {
  description = "Runtime of the Lambda function"
  value       = var.lambda_runtime
}

output "lambda_memory_size" {
  description = "Memory size of the Lambda function"
  value       = var.lambda_memory_size
}

output "lambda_timeout" {
  description = "Timeout of the Lambda function"
  value       = var.lambda_timeout
}

# Testing and Development Outputs
output "test_commands" {
  description = "Sample commands for testing the deployed infrastructure"
  value = {
    test_api_endpoint = "curl -X POST ${aws_api_gateway_stage.ethereum_stage.invoke_url}/ethereum -H 'Content-Type: application/json' -d '{\"action\":\"getBlockNumber\"}'"
    test_lambda_function = "aws lambda invoke --function-name ${aws_lambda_function.contract_manager.function_name} --payload '{\"action\":\"getBlockNumber\"}' response.json"
    check_node_status = "aws managedblockchain get-node --network-id ${var.ethereum_network} --node-id ${aws_managedblockchain_node.ethereum_node.id} --query 'Node.Status' --output text"
    list_contract_artifacts = "aws s3 ls s3://${aws_s3_bucket.contract_artifacts.bucket}/contracts/ --recursive"
  }
}

# Resource ARNs for reference
output "resource_arns" {
  description = "ARNs of all major resources created"
  value = {
    s3_bucket = aws_s3_bucket.contract_artifacts.arn
    lambda_function = aws_lambda_function.contract_manager.arn
    api_gateway = aws_api_gateway_rest_api.ethereum_api.arn
    lambda_role = aws_iam_role.lambda_role.arn
    blockchain_policy = aws_iam_policy.lambda_blockchain_policy.arn
    lambda_log_group = aws_cloudwatch_log_group.lambda_logs.arn
    api_gateway_log_group = aws_cloudwatch_log_group.api_gateway_logs.arn
  }
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Important notes about cost optimization"
  value = {
    blockchain_node_costs = "The Ethereum node (${var.blockchain_node_instance_type}) incurs ongoing costs. Consider using testnet for development."
    lambda_costs = "Lambda charges are based on requests and execution time. Monitor usage via CloudWatch."
    api_gateway_costs = "API Gateway charges per API call. Consider caching for high-traffic scenarios."
    storage_costs = "S3 storage costs depend on artifact size and access patterns. Enable lifecycle policies if needed."
    monitoring_costs = "CloudWatch logs and metrics have associated costs. Adjust retention periods as needed."
  }
}

# Security Information
output "security_notes" {
  description = "Important security considerations"
  value = {
    node_endpoints = "Node endpoints are stored in SSM Parameter Store for secure access."
    s3_access = "S3 bucket has public access blocked and uses server-side encryption."
    iam_permissions = "Lambda role follows least privilege principle with minimal required permissions."
    api_gateway = "API Gateway supports CORS and can be configured with API keys if needed."
    monitoring = "CloudWatch provides comprehensive logging and monitoring capabilities."
  }
}