# API Gateway Outputs
output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.main.name
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}"
}

output "api_endpoint_url" {
  description = "Full URL of the /data API endpoint"
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/data"
}

output "api_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.main.stage_name
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.api_backend.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.api_backend.arn
}

# Usage Plan Outputs
output "premium_usage_plan_id" {
  description = "ID of the Premium usage plan"
  value       = aws_api_gateway_usage_plan.premium.id
}

output "premium_usage_plan_name" {
  description = "Name of the Premium usage plan"
  value       = aws_api_gateway_usage_plan.premium.name
}

output "standard_usage_plan_id" {
  description = "ID of the Standard usage plan"
  value       = aws_api_gateway_usage_plan.standard.id
}

output "standard_usage_plan_name" {
  description = "Name of the Standard usage plan"
  value       = aws_api_gateway_usage_plan.standard.name
}

output "basic_usage_plan_id" {
  description = "ID of the Basic usage plan"
  value       = aws_api_gateway_usage_plan.basic.id
}

output "basic_usage_plan_name" {
  description = "Name of the Basic usage plan"
  value       = aws_api_gateway_usage_plan.basic.name
}

# API Key Outputs
output "premium_api_key_id" {
  description = "ID of the Premium API key"
  value       = aws_api_gateway_api_key.premium.id
}

output "premium_api_key_name" {
  description = "Name of the Premium API key"
  value       = aws_api_gateway_api_key.premium.name
}

output "standard_api_key_id" {
  description = "ID of the Standard API key"
  value       = aws_api_gateway_api_key.standard.id
}

output "standard_api_key_name" {
  description = "Name of the Standard API key"
  value       = aws_api_gateway_api_key.standard.name
}

output "basic_api_key_id" {
  description = "ID of the Basic API key"
  value       = aws_api_gateway_api_key.basic.id
}

output "basic_api_key_name" {
  description = "Name of the Basic API key"
  value       = aws_api_gateway_api_key.basic.name
}

# API Key Values (Sensitive)
output "premium_api_key_value" {
  description = "Value of the Premium API key"
  value       = aws_api_gateway_api_key.premium.value
  sensitive   = true
}

output "standard_api_key_value" {
  description = "Value of the Standard API key"
  value       = aws_api_gateway_api_key.standard.value
  sensitive   = true
}

output "basic_api_key_value" {
  description = "Value of the Basic API key"
  value       = aws_api_gateway_api_key.basic.value
  sensitive   = true
}

# Throttling Configuration Outputs
output "stage_throttle_settings" {
  description = "Stage-level throttling settings"
  value = {
    rate_limit  = var.stage_throttle_rate_limit
    burst_limit = var.stage_throttle_burst_limit
  }
}

output "usage_plan_throttle_settings" {
  description = "Usage plan throttling settings for all tiers"
  value = {
    premium = {
      rate_limit  = var.premium_rate_limit
      burst_limit = var.premium_burst_limit
      quota_limit = var.premium_quota_limit
    }
    standard = {
      rate_limit  = var.standard_rate_limit
      burst_limit = var.standard_burst_limit
      quota_limit = var.standard_quota_limit
    }
    basic = {
      rate_limit  = var.basic_rate_limit
      burst_limit = var.basic_burst_limit
      quota_limit = var.basic_quota_limit
    }
  }
}

# CloudWatch Alarm Outputs
output "cloudwatch_alarms" {
  description = "CloudWatch alarm information"
  value = var.enable_cloudwatch_alarms ? {
    throttling_alarm = {
      name = aws_cloudwatch_metric_alarm.api_high_throttling[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.api_high_throttling[0].arn
    }
    error_alarm = {
      name = aws_cloudwatch_metric_alarm.api_high_4xx_errors[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.api_high_4xx_errors[0].arn
    }
  } : null
}

# Testing Commands
output "testing_commands" {
  description = "Commands for testing the API with different keys"
  value = {
    test_without_key = "curl -X GET ${local.api_endpoint_url}"
    test_premium_key = "curl -X GET ${local.api_endpoint_url} -H \"X-API-Key: ${aws_api_gateway_api_key.premium.value}\""
    test_standard_key = "curl -X GET ${local.api_endpoint_url} -H \"X-API-Key: ${aws_api_gateway_api_key.standard.value}\""
    test_basic_key = "curl -X GET ${local.api_endpoint_url} -H \"X-API-Key: ${aws_api_gateway_api_key.basic.value}\""
    load_test_basic = "ab -n 1000 -c 10 -H \"X-API-Key: ${aws_api_gateway_api_key.basic.value}\" ${local.api_endpoint_url}"
    load_test_premium = "ab -n 1000 -c 50 -H \"X-API-Key: ${aws_api_gateway_api_key.premium.value}\" ${local.api_endpoint_url}"
  }
  sensitive = true
}

# Resource Information
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    api_gateway = {
      name = aws_api_gateway_rest_api.main.name
      id   = aws_api_gateway_rest_api.main.id
      url  = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}"
    }
    lambda_function = {
      name = aws_lambda_function.api_backend.function_name
      arn  = aws_lambda_function.api_backend.arn
    }
    usage_plans = {
      premium  = aws_api_gateway_usage_plan.premium.name
      standard = aws_api_gateway_usage_plan.standard.name
      basic    = aws_api_gateway_usage_plan.basic.name
    }
    api_keys = {
      premium  = aws_api_gateway_api_key.premium.name
      standard = aws_api_gateway_api_key.standard.name
      basic    = aws_api_gateway_api_key.basic.name
    }
  }
}

locals {
  api_endpoint_url = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.main.stage_name}/data"
}