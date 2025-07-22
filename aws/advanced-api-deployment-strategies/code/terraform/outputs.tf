# API Gateway Outputs
output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_api_gateway_rest_api.advanced_deployment_api.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway"
  value       = aws_api_gateway_rest_api.advanced_deployment_api.name
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.advanced_deployment_api.arn
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.advanced_deployment_api.execution_arn
}

# Production Stage Outputs
output "production_stage_url" {
  description = "URL of the production stage"
  value       = "https://${aws_api_gateway_rest_api.advanced_deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.production_stage.stage_name}"
}

output "production_stage_name" {
  description = "Name of the production stage"
  value       = aws_api_gateway_stage.production_stage.stage_name
}

output "production_stage_arn" {
  description = "ARN of the production stage"
  value       = aws_api_gateway_stage.production_stage.arn
}

# Staging Stage Outputs
output "staging_stage_url" {
  description = "URL of the staging stage"
  value       = "https://${aws_api_gateway_rest_api.advanced_deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.staging_stage.stage_name}"
}

output "staging_stage_name" {
  description = "Name of the staging stage"
  value       = aws_api_gateway_stage.staging_stage.stage_name
}

output "staging_stage_arn" {
  description = "ARN of the staging stage"
  value       = aws_api_gateway_stage.staging_stage.arn
}

# API Endpoints
output "production_hello_endpoint" {
  description = "Production Hello API endpoint"
  value       = "https://${aws_api_gateway_rest_api.advanced_deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.production_stage.stage_name}/hello"
}

output "staging_hello_endpoint" {
  description = "Staging Hello API endpoint"
  value       = "https://${aws_api_gateway_rest_api.advanced_deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.staging_stage.stage_name}/hello"
}

# Lambda Function Outputs
output "blue_lambda_function_name" {
  description = "Name of the Blue Lambda function"
  value       = aws_lambda_function.blue_function.function_name
}

output "blue_lambda_function_arn" {
  description = "ARN of the Blue Lambda function"
  value       = aws_lambda_function.blue_function.arn
}

output "blue_lambda_function_invoke_arn" {
  description = "Invoke ARN of the Blue Lambda function"
  value       = aws_lambda_function.blue_function.invoke_arn
}

output "green_lambda_function_name" {
  description = "Name of the Green Lambda function"
  value       = aws_lambda_function.green_function.function_name
}

output "green_lambda_function_arn" {
  description = "ARN of the Green Lambda function"
  value       = aws_lambda_function.green_function.arn
}

output "green_lambda_function_invoke_arn" {
  description = "Invoke ARN of the Green Lambda function"
  value       = aws_lambda_function.green_function.invoke_arn
}

# IAM Role Outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch Alarms Outputs
output "api_4xx_errors_alarm_name" {
  description = "Name of the API Gateway 4XX errors alarm"
  value       = aws_cloudwatch_metric_alarm.api_4xx_errors.alarm_name
}

output "api_5xx_errors_alarm_name" {
  description = "Name of the API Gateway 5XX errors alarm"
  value       = aws_cloudwatch_metric_alarm.api_5xx_errors.alarm_name
}

output "api_high_latency_alarm_name" {
  description = "Name of the API Gateway high latency alarm"
  value       = aws_cloudwatch_metric_alarm.api_high_latency.alarm_name
}

output "blue_lambda_errors_alarm_name" {
  description = "Name of the Blue Lambda function errors alarm"
  value       = aws_cloudwatch_metric_alarm.blue_lambda_errors.alarm_name
}

output "green_lambda_errors_alarm_name" {
  description = "Name of the Green Lambda function errors alarm"
  value       = aws_cloudwatch_metric_alarm.green_lambda_errors.alarm_name
}

# Dead Letter Queue Output (if enabled)
output "lambda_dlq_url" {
  description = "URL of the Lambda Dead Letter Queue"
  value       = var.enable_dlq ? aws_sqs_queue.lambda_dlq[0].url : null
}

output "lambda_dlq_arn" {
  description = "ARN of the Lambda Dead Letter Queue"
  value       = var.enable_dlq ? aws_sqs_queue.lambda_dlq[0].arn : null
}

# Custom Domain Outputs (if configured)
output "custom_domain_name" {
  description = "Custom domain name for the API"
  value       = var.custom_domain_name != null ? aws_api_gateway_domain_name.custom_domain[0].domain_name : null
}

output "custom_domain_target_domain_name" {
  description = "Target domain name for the custom domain"
  value       = var.custom_domain_name != null ? aws_api_gateway_domain_name.custom_domain[0].regional_domain_name : null
}

output "custom_domain_hosted_zone_id" {
  description = "Hosted zone ID for the custom domain"
  value       = var.custom_domain_name != null ? aws_api_gateway_domain_name.custom_domain[0].regional_zone_id : null
}

# Canary Deployment Configuration
output "canary_deployment_enabled" {
  description = "Whether canary deployment is enabled"
  value       = var.enable_canary_deployment
}

output "canary_traffic_percentage" {
  description = "Percentage of traffic routed to canary deployment"
  value       = var.enable_canary_deployment ? var.canary_percent_traffic : 0
}

# Deployment Information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "deployment_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Monitoring and Logging
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for API Gateway"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_log_group[0].name : null
}

output "xray_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled"
  value       = var.enable_xray_tracing
}

# API Gateway Method Settings
output "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit per second"
  value       = var.api_throttle_rate_limit
}

output "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  value       = var.api_throttle_burst_limit
}

# Testing Commands
output "test_commands" {
  description = "Commands to test the deployed API"
  value = {
    test_blue_production = "curl -s https://${aws_api_gateway_rest_api.advanced_deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.production_stage.stage_name}/hello | jq '.'"
    test_green_staging   = "curl -s https://${aws_api_gateway_rest_api.advanced_deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.staging_stage.stage_name}/hello | jq '.'"
    test_canary_traffic  = "for i in {1..20}; do curl -s https://${aws_api_gateway_rest_api.advanced_deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.production_stage.stage_name}/hello | jq -r '.environment'; sleep 1; done"
  }
}

# CloudWatch Dashboard URLs
output "cloudwatch_dashboard_urls" {
  description = "URLs to CloudWatch dashboards for monitoring"
  value = {
    api_gateway_metrics = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS%2FApiGateway%20ApiName%20${aws_api_gateway_rest_api.advanced_deployment_api.name}"
    lambda_metrics      = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();query=AWS%2FLambda"
    alarms              = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:"
  }
}

# Terraform State Information
output "terraform_state_info" {
  description = "Information about Terraform state management"
  value = {
    workspace = terraform.workspace
    backend   = "local"
    version   = "~> 1.0"
  }
}