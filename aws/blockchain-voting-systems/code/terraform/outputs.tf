# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for voting system data"
  value       = aws_s3_bucket.voting_system_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for voting system data"
  value       = aws_s3_bucket.voting_system_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.voting_system_data.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.voting_system_data.bucket_regional_domain_name
}

# DynamoDB Table Outputs
output "voter_registry_table_name" {
  description = "Name of the DynamoDB table for voter registry"
  value       = aws_dynamodb_table.voter_registry.name
}

output "voter_registry_table_arn" {
  description = "ARN of the DynamoDB table for voter registry"
  value       = aws_dynamodb_table.voter_registry.arn
}

output "elections_table_name" {
  description = "Name of the DynamoDB table for elections"
  value       = aws_dynamodb_table.elections.name
}

output "elections_table_arn" {
  description = "ARN of the DynamoDB table for elections"
  value       = aws_dynamodb_table.elections.arn
}

# Lambda Function Outputs
output "voter_auth_function_name" {
  description = "Name of the voter authentication Lambda function"
  value       = aws_lambda_function.voter_auth.function_name
}

output "voter_auth_function_arn" {
  description = "ARN of the voter authentication Lambda function"
  value       = aws_lambda_function.voter_auth.arn
}

output "vote_monitor_function_name" {
  description = "Name of the vote monitoring Lambda function"
  value       = aws_lambda_function.vote_monitor.function_name
}

output "vote_monitor_function_arn" {
  description = "ARN of the vote monitoring Lambda function"
  value       = aws_lambda_function.vote_monitor.arn
}

# Cognito Outputs
output "cognito_user_pool_id" {
  description = "ID of the Cognito user pool"
  value       = aws_cognito_user_pool.voter_pool.id
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito user pool"
  value       = aws_cognito_user_pool.voter_pool.arn
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito user pool client"
  value       = aws_cognito_user_pool_client.voter_pool_client.id
}

output "cognito_user_pool_domain" {
  description = "Domain name of the Cognito user pool"
  value       = aws_cognito_user_pool.voter_pool.domain
}

# KMS Key Outputs
output "kms_key_id" {
  description = "ID of the KMS key for encryption"
  value       = aws_kms_key.voting_system_key.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  value       = aws_kms_key.voting_system_key.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key for encryption"
  value       = aws_kms_alias.voting_system_key_alias.name
}

# SNS Topic Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for voting notifications"
  value       = aws_sns_topic.voting_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for voting notifications"
  value       = aws_sns_topic.voting_notifications.name
}

# EventBridge Outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for voting events"
  value       = aws_cloudwatch_event_rule.voting_events.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for voting events"
  value       = aws_cloudwatch_event_rule.voting_events.arn
}

output "eventbridge_archive_name" {
  description = "Name of the EventBridge archive (if enabled)"
  value       = var.enable_eventbridge_archive ? aws_cloudwatch_event_archive.voting_events_archive[0].name : null
}

# API Gateway Outputs
output "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.voting_api.id
}

output "api_gateway_rest_api_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.voting_api.arn
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.voting_api.execution_arn
}

output "api_gateway_url" {
  description = "URL of the API Gateway REST API"
  value       = "https://${aws_api_gateway_rest_api.voting_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.voting_api_stage.stage_name
}

# CloudWatch Outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.voting_system_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.voting_system_dashboard.dashboard_name}"
}

# IAM Role Outputs
output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# CloudWatch Log Group Outputs
output "voter_auth_log_group_name" {
  description = "Name of the CloudWatch log group for voter authentication"
  value       = aws_cloudwatch_log_group.voter_auth_logs.name
}

output "vote_monitor_log_group_name" {
  description = "Name of the CloudWatch log group for vote monitoring"
  value       = aws_cloudwatch_log_group.vote_monitor_logs.name
}

output "api_gateway_log_group_name" {
  description = "Name of the CloudWatch log group for API Gateway"
  value       = aws_cloudwatch_log_group.api_gateway_logs.name
}

# CloudWatch Alarm Outputs
output "voter_auth_errors_alarm_name" {
  description = "Name of the CloudWatch alarm for voter authentication errors"
  value       = aws_cloudwatch_metric_alarm.voter_auth_errors.alarm_name
}

output "vote_monitor_errors_alarm_name" {
  description = "Name of the CloudWatch alarm for vote monitoring errors"
  value       = aws_cloudwatch_metric_alarm.vote_monitor_errors.alarm_name
}

output "dynamodb_throttles_alarm_name" {
  description = "Name of the CloudWatch alarm for DynamoDB throttling"
  value       = aws_cloudwatch_metric_alarm.dynamodb_throttles.alarm_name
}

# Environment Variables for Lambda Functions
output "lambda_environment_variables" {
  description = "Environment variables for Lambda functions"
  value = {
    voter_auth = {
      KMS_KEY_ID       = aws_kms_key.voting_system_key.key_id
      VOTER_TABLE_NAME = aws_dynamodb_table.voter_registry.name
      BUCKET_NAME      = aws_s3_bucket.voting_system_data.bucket
    }
    vote_monitor = {
      BUCKET_NAME          = aws_s3_bucket.voting_system_data.bucket
      ELECTIONS_TABLE_NAME = aws_dynamodb_table.elections.name
      SNS_TOPIC_ARN        = aws_sns_topic.voting_notifications.arn
    }
  }
}

# Blockchain Node Creation Instructions
output "blockchain_node_creation_instructions" {
  description = "Instructions for creating the blockchain node manually"
  value       = local.blockchain_creation_instructions
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    region                = data.aws_region.current.name
    account_id            = data.aws_caller_identity.current.account_id
    project_name          = var.project_name
    environment           = var.environment
    s3_bucket            = aws_s3_bucket.voting_system_data.bucket
    voter_registry_table = aws_dynamodb_table.voter_registry.name
    elections_table      = aws_dynamodb_table.elections.name
    lambda_auth_function = aws_lambda_function.voter_auth.function_name
    lambda_monitor_function = aws_lambda_function.vote_monitor.function_name
    cognito_user_pool    = aws_cognito_user_pool.voter_pool.id
    api_gateway_url      = "https://${aws_api_gateway_rest_api.voting_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
    kms_key_id           = aws_kms_key.voting_system_key.key_id
    sns_topic_arn        = aws_sns_topic.voting_notifications.arn
    dashboard_name       = aws_cloudwatch_dashboard.voting_system_dashboard.dashboard_name
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    1. Create blockchain node manually using the provided CLI command
    2. Upload Lambda deployment packages (voter-auth-lambda.zip and vote-monitor-lambda.zip)
    3. Deploy smart contracts to the blockchain network
    4. Configure Cognito user pool with initial admin users
    5. Set up SNS topic subscription for notifications
    6. Upload voting DApp to S3 bucket
    7. Test the complete voting system workflow
    8. Configure monitoring and alerting thresholds
  EOT
}