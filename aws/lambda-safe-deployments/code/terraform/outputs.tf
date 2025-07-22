# =====================================================
# Lambda Function Outputs
# =====================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.deployment_demo.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.deployment_demo.arn
}

output "lambda_function_version_1" {
  description = "Version number of Lambda function V1 (Blue)"
  value       = aws_lambda_function.deployment_demo_v1.version
}

output "lambda_function_version_2" {
  description = "Version number of Lambda function V2 (Green)"
  value       = aws_lambda_function.deployment_demo_v2.version
}

output "lambda_production_alias_arn" {
  description = "ARN of the production alias"
  value       = aws_lambda_alias.production.arn
}

output "lambda_production_alias_name" {
  description = "Name of the production alias"
  value       = aws_lambda_alias.production.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# =====================================================
# API Gateway Outputs
# =====================================================

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_api_gateway_rest_api.deployment_api.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway"
  value       = aws_api_gateway_rest_api.deployment_api.name
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.deployment_api.execution_arn
}

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = "https://${aws_api_gateway_rest_api.deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/demo"
}

output "api_gateway_stage_name" {
  description = "Stage name of the API Gateway deployment"
  value       = var.api_stage_name
}

# =====================================================
# CloudWatch Monitoring Outputs
# =====================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "lambda_error_alarm_name" {
  description = "Name of the Lambda error rate alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_error_alarm.alarm_name
}

output "lambda_duration_alarm_name" {
  description = "Name of the Lambda duration alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_duration_alarm.alarm_name
}

output "api_gateway_4xx_alarm_name" {
  description = "Name of the API Gateway 4xx error alarm"
  value       = aws_cloudwatch_metric_alarm.api_gateway_4xx_alarm.alarm_name
}

output "api_gateway_5xx_alarm_name" {
  description = "Name of the API Gateway 5xx error alarm"
  value       = aws_cloudwatch_metric_alarm.api_gateway_5xx_alarm.alarm_name
}

# =====================================================
# Deployment Configuration Outputs
# =====================================================

output "canary_deployment_enabled" {
  description = "Whether canary deployment is enabled"
  value       = var.enable_canary_deployment
}

output "canary_traffic_percentage" {
  description = "Percentage of traffic routed to canary version"
  value       = var.canary_traffic_percentage
}

output "blue_green_deployment_enabled" {
  description = "Whether blue-green deployment is enabled"
  value       = var.enable_blue_green_deployment
}

output "current_deployment_version" {
  description = "Current version receiving traffic through production alias"
  value       = aws_lambda_alias.production.function_version
}

# =====================================================
# Testing and Validation Outputs
# =====================================================

output "test_commands" {
  description = "Commands to test the deployment patterns"
  value = {
    test_api_endpoint = "curl -s ${aws_api_gateway_rest_api.deployment_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/demo | jq ."
    test_lambda_direct = "aws lambda invoke --function-name ${aws_lambda_function.deployment_demo.function_name}:production --payload '{}' response.json && cat response.json | jq ."
    get_alias_config = "aws lambda get-alias --function-name ${aws_lambda_function.deployment_demo.function_name} --name production"
    list_versions = "aws lambda list-versions-by-function --function-name ${aws_lambda_function.deployment_demo.function_name}"
  }
}

# =====================================================
# Resource Information Outputs
# =====================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_names" {
  description = "Names of all created resources"
  value = {
    lambda_function = local.function_name
    api_gateway     = local.api_name
    iam_role        = local.role_name
    log_group       = "/aws/lambda/${local.function_name}"
  }
}

# =====================================================
# Rollback Information Outputs
# =====================================================

output "rollback_commands" {
  description = "Commands to rollback deployments"
  value = {
    rollback_to_v1 = "aws lambda update-alias --function-name ${aws_lambda_function.deployment_demo.function_name} --name production --function-version ${aws_lambda_function.deployment_demo_v1.version} --routing-config '{}'"
    rollback_to_v2 = "aws lambda update-alias --function-name ${aws_lambda_function.deployment_demo.function_name} --name production --function-version ${aws_lambda_function.deployment_demo_v2.version} --routing-config '{}'"
    enable_canary = "aws lambda update-alias --function-name ${aws_lambda_function.deployment_demo.function_name} --name production --function-version ${aws_lambda_function.deployment_demo_v2.version} --routing-config '{\"AdditionalVersionWeights\":{\"${aws_lambda_function.deployment_demo_v1.version}\":0.9}}'"
  }
}

# =====================================================
# Cost Optimization Outputs
# =====================================================

output "cost_optimization_notes" {
  description = "Notes about cost optimization for the deployment"
  value = {
    lambda_cost_factors = "Lambda costs are based on requests and execution time. Monitor usage through CloudWatch."
    api_gateway_cost_factors = "API Gateway costs are based on API calls and data transfer. Consider caching for frequently accessed endpoints."
    cloudwatch_cost_factors = "CloudWatch costs include log storage and metric monitoring. Adjust retention periods based on requirements."
    cleanup_reminder = "Remember to run 'terraform destroy' to clean up resources when no longer needed."
  }
}