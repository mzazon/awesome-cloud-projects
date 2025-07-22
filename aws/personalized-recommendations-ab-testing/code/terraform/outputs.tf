# API Gateway Outputs
output "api_gateway_url" {
  description = "URL of the API Gateway for recommendation requests"
  value       = aws_apigatewayv2_stage.recommendation_api_stage.invoke_url
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.recommendation_api.id
}

output "recommendations_endpoint" {
  description = "Full URL for the recommendations endpoint"
  value       = "${aws_apigatewayv2_stage.recommendation_api_stage.invoke_url}/recommendations"
}

output "events_endpoint" {
  description = "Full URL for the events tracking endpoint"
  value       = "${aws_apigatewayv2_stage.recommendation_api_stage.invoke_url}/events"
}

# S3 Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Personalize training data"
  value       = aws_s3_bucket.personalize_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Personalize training data"
  value       = aws_s3_bucket.personalize_data.arn
}

# DynamoDB Outputs
output "dynamodb_users_table_name" {
  description = "Name of the DynamoDB users table"
  value       = aws_dynamodb_table.users.name
}

output "dynamodb_users_table_arn" {
  description = "ARN of the DynamoDB users table"
  value       = aws_dynamodb_table.users.arn
}

output "dynamodb_items_table_name" {
  description = "Name of the DynamoDB items table"
  value       = aws_dynamodb_table.items.name
}

output "dynamodb_items_table_arn" {
  description = "ARN of the DynamoDB items table"
  value       = aws_dynamodb_table.items.arn
}

output "dynamodb_ab_assignments_table_name" {
  description = "Name of the DynamoDB A/B test assignments table"
  value       = aws_dynamodb_table.ab_assignments.name
}

output "dynamodb_ab_assignments_table_arn" {
  description = "ARN of the DynamoDB A/B test assignments table"
  value       = aws_dynamodb_table.ab_assignments.arn
}

output "dynamodb_events_table_name" {
  description = "Name of the DynamoDB events table"
  value       = aws_dynamodb_table.events.name
}

output "dynamodb_events_table_arn" {
  description = "ARN of the DynamoDB events table"
  value       = aws_dynamodb_table.events.arn
}

# Lambda Function Outputs
output "lambda_ab_test_router_function_name" {
  description = "Name of the A/B test router Lambda function"
  value       = aws_lambda_function.ab_test_router.function_name
}

output "lambda_ab_test_router_function_arn" {
  description = "ARN of the A/B test router Lambda function"
  value       = aws_lambda_function.ab_test_router.arn
}

output "lambda_recommendation_engine_function_name" {
  description = "Name of the recommendation engine Lambda function"
  value       = aws_lambda_function.recommendation_engine.function_name
}

output "lambda_recommendation_engine_function_arn" {
  description = "ARN of the recommendation engine Lambda function"
  value       = aws_lambda_function.recommendation_engine.arn
}

output "lambda_event_tracker_function_name" {
  description = "Name of the event tracker Lambda function"
  value       = aws_lambda_function.event_tracker.function_name
}

output "lambda_event_tracker_function_arn" {
  description = "ARN of the event tracker Lambda function"
  value       = aws_lambda_function.event_tracker.arn
}

output "lambda_personalize_manager_function_name" {
  description = "Name of the Personalize manager Lambda function"
  value       = aws_lambda_function.personalize_manager.function_name
}

output "lambda_personalize_manager_function_arn" {
  description = "ARN of the Personalize manager Lambda function"
  value       = aws_lambda_function.personalize_manager.arn
}

# IAM Role Outputs
output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "personalize_role_arn" {
  description = "ARN of the Personalize service role"
  value       = aws_iam_role.personalize_role.arn
}

# KMS Key Outputs
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.personalize_key.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.personalize_key.arn
}

output "kms_alias_name" {
  description = "Name of the KMS key alias"
  value       = aws_kms_alias.personalize_key.name
}

# CloudWatch Outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.personalize_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.personalize_dashboard.dashboard_name}"
}

# Resource Names for Script Usage
output "project_name_with_suffix" {
  description = "Project name with random suffix for unique resource naming"
  value       = local.name_prefix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = local.region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = local.account_id
}

# A/B Testing Configuration
output "ab_test_variants" {
  description = "A/B test variant configuration"
  value       = var.ab_test_variants
}

# Personalize Configuration
output "personalize_recipes" {
  description = "Personalize recipe configurations for A/B testing"
  value       = var.personalize_recipes
}

# Cost Tracking Information
output "cost_allocation_tags" {
  description = "Tags used for cost allocation and tracking"
  value = {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "real-time-recommendations-personalize-ab-testing"
    ManagedBy   = "terraform"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration summary"
  value = {
    encryption_at_rest = "All data encrypted with customer-managed KMS key"
    kms_key_id        = aws_kms_key.personalize_key.key_id
    iam_roles = {
      lambda_role      = aws_iam_role.lambda_role.name
      personalize_role = aws_iam_role.personalize_role.name
    }
    s3_public_access_blocked = true
    dynamodb_encryption      = "Enabled with KMS"
    vpc_endpoints           = var.enable_vpc_endpoints ? "Enabled" : "Disabled"
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    test_ab_assignment = "aws lambda invoke --function-name ${aws_lambda_function.ab_test_router.function_name} --payload '{\"user_id\": \"test-user-001\"}' response.json && cat response.json"
    test_event_tracking = "curl -X POST ${aws_apigatewayv2_stage.recommendation_api_stage.invoke_url}/events -H 'Content-Type: application/json' -d '{\"user_id\": \"test-user-001\", \"event_type\": \"view\", \"item_id\": \"test-item-001\"}'"
    view_dashboard = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.personalize_dashboard.dashboard_name}"
    view_api_logs = "aws logs describe-log-groups --log-group-name-prefix /aws/apigateway/${local.name_prefix}"
  }
}

# Data Loading Commands
output "data_loading_commands" {
  description = "Commands for loading sample data into DynamoDB"
  value = {
    upload_to_s3 = "aws s3 cp sample-data/ s3://${aws_s3_bucket.personalize_data.bucket}/training-data/ --recursive"
    load_users_data = "# Use AWS CLI or SDK to load user data into ${aws_dynamodb_table.users.name}"
    load_items_data = "# Use AWS CLI or SDK to load item data into ${aws_dynamodb_table.items.name}"
  }
}

# Monitoring and Alerting
output "monitoring_resources" {
  description = "Monitoring and alerting resources created"
  value = {
    dashboard_name = aws_cloudwatch_dashboard.personalize_dashboard.dashboard_name
    log_groups = [
      aws_cloudwatch_log_group.ab_test_router_logs.name,
      aws_cloudwatch_log_group.recommendation_engine_logs.name,
      aws_cloudwatch_log_group.event_tracker_logs.name,
      aws_cloudwatch_log_group.personalize_manager_logs.name,
      aws_cloudwatch_log_group.api_gateway_logs.name
    ]
    alarms_created = length(aws_cloudwatch_metric_alarm.lambda_error_rate)
  }
}