# Outputs for multi-region active-active application with Global Accelerator

# ============================================================================
# Global Accelerator Outputs
# ============================================================================

output "global_accelerator_arn" {
  description = "ARN of the Global Accelerator"
  value       = aws_globalaccelerator_accelerator.main.id
}

output "global_accelerator_dns_name" {
  description = "DNS name of the Global Accelerator"
  value       = aws_globalaccelerator_accelerator.main.dns_name
}

output "global_accelerator_hosted_zone_id" {
  description = "Hosted zone ID of the Global Accelerator"
  value       = aws_globalaccelerator_accelerator.main.hosted_zone_id
}

output "global_accelerator_static_ips" {
  description = "Static IP addresses of the Global Accelerator"
  value       = aws_globalaccelerator_accelerator.main.ip_sets[0].ip_addresses
}

output "global_accelerator_listener_arn" {
  description = "ARN of the Global Accelerator listener"
  value       = aws_globalaccelerator_listener.main.id
}

# ============================================================================
# Application Load Balancer Outputs
# ============================================================================

output "alb_us_arn" {
  description = "ARN of the US Application Load Balancer"
  value       = aws_lb.app_lb_us.arn
}

output "alb_us_dns_name" {
  description = "DNS name of the US Application Load Balancer"
  value       = aws_lb.app_lb_us.dns_name
}

output "alb_us_zone_id" {
  description = "Hosted zone ID of the US Application Load Balancer"
  value       = aws_lb.app_lb_us.zone_id
}

output "alb_eu_arn" {
  description = "ARN of the EU Application Load Balancer"
  value       = aws_lb.app_lb_eu.arn
}

output "alb_eu_dns_name" {
  description = "DNS name of the EU Application Load Balancer"
  value       = aws_lb.app_lb_eu.dns_name
}

output "alb_eu_zone_id" {
  description = "Hosted zone ID of the EU Application Load Balancer"
  value       = aws_lb.app_lb_eu.zone_id
}

output "alb_asia_arn" {
  description = "ARN of the Asia Application Load Balancer"
  value       = aws_lb.app_lb_asia.arn
}

output "alb_asia_dns_name" {
  description = "DNS name of the Asia Application Load Balancer"
  value       = aws_lb.app_lb_asia.dns_name
}

output "alb_asia_zone_id" {
  description = "Hosted zone ID of the Asia Application Load Balancer"
  value       = aws_lb.app_lb_asia.zone_id
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_function_us_arn" {
  description = "ARN of the US Lambda function"
  value       = aws_lambda_function.app_function_us.arn
}

output "lambda_function_us_name" {
  description = "Name of the US Lambda function"
  value       = aws_lambda_function.app_function_us.function_name
}

output "lambda_function_eu_arn" {
  description = "ARN of the EU Lambda function"
  value       = aws_lambda_function.app_function_eu.arn
}

output "lambda_function_eu_name" {
  description = "Name of the EU Lambda function"
  value       = aws_lambda_function.app_function_eu.function_name
}

output "lambda_function_asia_arn" {
  description = "ARN of the Asia Lambda function"
  value       = aws_lambda_function.app_function_asia.arn
}

output "lambda_function_asia_name" {
  description = "Name of the Asia Lambda function"
  value       = aws_lambda_function.app_function_asia.function_name
}

# ============================================================================
# DynamoDB Outputs
# ============================================================================

output "dynamodb_global_table_name" {
  description = "Name of the DynamoDB Global Table"
  value       = aws_dynamodb_global_table.global_user_data.name
}

output "dynamodb_table_us_arn" {
  description = "ARN of the US DynamoDB table"
  value       = aws_dynamodb_table.global_table_us.arn
}

output "dynamodb_table_eu_arn" {
  description = "ARN of the EU DynamoDB table"
  value       = aws_dynamodb_table.global_table_eu.arn
}

output "dynamodb_table_asia_arn" {
  description = "ARN of the Asia DynamoDB table"
  value       = aws_dynamodb_table.global_table_asia.arn
}

output "dynamodb_stream_us_arn" {
  description = "ARN of the US DynamoDB stream"
  value       = aws_dynamodb_table.global_table_us.stream_arn
}

output "dynamodb_stream_eu_arn" {
  description = "ARN of the EU DynamoDB stream"
  value       = aws_dynamodb_table.global_table_eu.stream_arn
}

output "dynamodb_stream_asia_arn" {
  description = "ARN of the Asia DynamoDB stream"
  value       = aws_dynamodb_table.global_table_asia.stream_arn
}

# ============================================================================
# Target Group Outputs
# ============================================================================

output "target_group_us_arn" {
  description = "ARN of the US target group"
  value       = aws_lb_target_group.lambda_tg_us.arn
}

output "target_group_eu_arn" {
  description = "ARN of the EU target group"
  value       = aws_lb_target_group.lambda_tg_eu.arn
}

output "target_group_asia_arn" {
  description = "ARN of the Asia target group"
  value       = aws_lb_target_group.lambda_tg_asia.arn
}

# ============================================================================
# Endpoint Group Outputs
# ============================================================================

output "endpoint_group_us_arn" {
  description = "ARN of the US endpoint group"
  value       = aws_globalaccelerator_endpoint_group.us.id
}

output "endpoint_group_eu_arn" {
  description = "ARN of the EU endpoint group"
  value       = aws_globalaccelerator_endpoint_group.eu.id
}

output "endpoint_group_asia_arn" {
  description = "ARN of the Asia endpoint group"
  value       = aws_globalaccelerator_endpoint_group.asia.id
}

# ============================================================================
# IAM Outputs
# ============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# ============================================================================
# CloudWatch Log Group Outputs
# ============================================================================

output "lambda_log_group_us_name" {
  description = "Name of the US Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs_us.name
}

output "lambda_log_group_eu_name" {
  description = "Name of the EU Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs_eu.name
}

output "lambda_log_group_asia_name" {
  description = "Name of the Asia Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs_asia.name
}

# ============================================================================
# S3 Bucket Outputs (conditional)
# ============================================================================

output "flow_logs_bucket_name" {
  description = "Name of the S3 bucket for Global Accelerator flow logs"
  value       = var.enable_detailed_monitoring ? aws_s3_bucket.flow_logs[0].bucket : ""
}

output "flow_logs_bucket_arn" {
  description = "ARN of the S3 bucket for Global Accelerator flow logs"
  value       = var.enable_detailed_monitoring ? aws_s3_bucket.flow_logs[0].arn : ""
}

# ============================================================================
# Regional Information Outputs
# ============================================================================

output "regions" {
  description = "Map of regions used in the deployment"
  value = {
    primary_region        = var.primary_region
    secondary_region_eu   = var.secondary_region_eu
    secondary_region_asia = var.secondary_region_asia
  }
}

# ============================================================================
# Application Endpoints
# ============================================================================

output "application_endpoints" {
  description = "Application endpoints for testing"
  value = {
    global_accelerator = "http://${aws_globalaccelerator_accelerator.main.dns_name}"
    static_ips = [
      for ip in aws_globalaccelerator_accelerator.main.ip_sets[0].ip_addresses :
      "http://${ip}"
    ]
    regional_endpoints = {
      us_east = "http://${aws_lb.app_lb_us.dns_name}"
      eu_west = "http://${aws_lb.app_lb_eu.dns_name}"
      asia_southeast = "http://${aws_lb.app_lb_asia.dns_name}"
    }
  }
}

# ============================================================================
# Testing and Validation Commands
# ============================================================================

output "validation_commands" {
  description = "Commands for testing the deployment"
  value = {
    health_check_global = "curl -s http://${aws_globalaccelerator_accelerator.main.dns_name}/health | jq ."
    health_check_us = "curl -s http://${aws_lb.app_lb_us.dns_name}/health | jq ."
    health_check_eu = "curl -s http://${aws_lb.app_lb_eu.dns_name}/health | jq ."
    health_check_asia = "curl -s http://${aws_lb.app_lb_asia.dns_name}/health | jq ."
    test_user_creation = "curl -X POST http://${aws_globalaccelerator_accelerator.main.dns_name}/user -H 'Content-Type: application/json' -d '{\"userId\":\"test-$(date +%s)\",\"data\":{\"name\":\"Test User\"}}'"
    list_users = "curl -s http://${aws_globalaccelerator_accelerator.main.dns_name}/users | jq ."
  }
}

# ============================================================================
# Resource Summary
# ============================================================================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    global_accelerator = {
      name = aws_globalaccelerator_accelerator.main.name
      dns_name = aws_globalaccelerator_accelerator.main.dns_name
      static_ips = aws_globalaccelerator_accelerator.main.ip_sets[0].ip_addresses
    }
    dynamodb_global_table = {
      name = aws_dynamodb_global_table.global_user_data.name
      regions = [var.primary_region, var.secondary_region_eu, var.secondary_region_asia]
    }
    lambda_functions = {
      us_east = aws_lambda_function.app_function_us.function_name
      eu_west = aws_lambda_function.app_function_eu.function_name
      asia_southeast = aws_lambda_function.app_function_asia.function_name
    }
    load_balancers = {
      us_east = aws_lb.app_lb_us.dns_name
      eu_west = aws_lb.app_lb_eu.dns_name
      asia_southeast = aws_lb.app_lb_asia.dns_name
    }
  }
}

# ============================================================================
# Random Suffix (for reference)
# ============================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}