# Outputs for serverless web applications with Amplify and Lambda
# This file defines all the outputs that will be displayed after deployment

###########################################
# Application URLs and Endpoints
###########################################

output "amplify_app_url" {
  description = "URL of the Amplify hosted web application"
  value       = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.todo_app.default_domain}"
}

output "amplify_app_id" {
  description = "Amplify application ID"
  value       = aws_amplify_app.todo_app.id
}

output "api_gateway_url" {
  description = "API Gateway endpoint URL for the REST API"
  value       = aws_api_gateway_stage.todo_api.invoke_url
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.todo_api.id
}

###########################################
# Authentication Configuration
###########################################

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for authentication"
  value       = aws_cognito_user_pool.users.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.users.arn
}

output "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID for web applications"
  value       = aws_cognito_user_pool_client.web_client.id
}

output "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID for AWS resource access"
  value       = aws_cognito_identity_pool.main.id
}

output "cognito_user_pool_domain" {
  description = "Cognito User Pool domain for hosted UI (if configured)"
  value       = aws_cognito_user_pool.users.domain
}

###########################################
# Backend Resources
###########################################

output "lambda_function_name" {
  description = "Name of the Lambda function handling API requests"
  value       = aws_lambda_function.todo_api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.todo_api.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing todo items"
  value       = aws_dynamodb_table.todos.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.todos.arn
}

###########################################
# Environment Configuration
###########################################

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "environment" {
  description = "Environment name (dev, staging, prod)"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

###########################################
# Resource Identifiers
###########################################

output "resource_prefix" {
  description = "Common prefix used for all resource names"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

###########################################
# IAM Roles and Policies
###########################################

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "cognito_authenticated_role_arn" {
  description = "ARN of the Cognito authenticated users role"
  value       = aws_iam_role.cognito_authenticated_role.arn
}

###########################################
# Monitoring and Logging
###########################################

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.todo_app_dashboard.dashboard_name}"
}

output "lambda_log_group_name" {
  description = "CloudWatch Log Group name for Lambda function logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : "CloudWatch logging disabled"
}

output "api_gateway_log_group_name" {
  description = "CloudWatch Log Group name for API Gateway logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.api_gateway_logs[0].name : "CloudWatch logging disabled"
}

###########################################
# Configuration for Frontend Integration
###########################################

output "frontend_config" {
  description = "Configuration object for frontend application integration"
  value = {
    region = data.aws_region.current.name
    auth = {
      userPoolId                = aws_cognito_user_pool.users.id
      userPoolWebClientId       = aws_cognito_user_pool_client.web_client.id
      identityPoolId           = aws_cognito_identity_pool.main.id
    }
    api = {
      invokeUrl = aws_api_gateway_stage.todo_api.invoke_url
      region    = data.aws_region.current.name
    }
    storage = {
      tableName = aws_dynamodb_table.todos.name
    }
  }
  sensitive = false
}

###########################################
# Deployment Information
###########################################

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

###########################################
# Cost Optimization Information
###########################################

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for resources (excluding data transfer and API calls)"
  value = {
    description = "Cost estimates are approximate and vary based on usage"
    amplify_hosting = "$0.01 per build minute + $0.15 per GB served"
    lambda = "First 1M requests free, then $0.20 per 1M requests + $0.0000166667 per GB-second"
    api_gateway = "$3.50 per million API calls"
    dynamodb = var.dynamodb_billing_mode == "PAY_PER_REQUEST" ? "$1.25 per million read requests + $1.25 per million write requests" : "Provisioned capacity pricing"
    cognito = "First 50,000 MAUs free, then $0.0055 per MAU"
    cloudwatch = "$0.50 per million requests + log storage costs"
  }
}

###########################################
# Security Information
###########################################

output "security_considerations" {
  description = "Important security considerations for the deployed resources"
  value = {
    authentication = "Users must authenticate through Cognito User Pool"
    api_access = "API Gateway uses IAM authentication for all endpoints"
    data_encryption = "DynamoDB table has server-side encryption enabled"
    network_security = "All resources use HTTPS/TLS encryption in transit"
    monitoring = "CloudWatch logs and metrics are enabled for observability"
  }
}

###########################################
# Next Steps Information
###########################################

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    frontend_deployment = "Deploy your React application to the Amplify app using the provided configuration"
    testing = "Test the API endpoints using the provided URL and authentication"
    monitoring = "Set up CloudWatch alarms for Lambda errors and API Gateway latency"
    custom_domain = "Configure a custom domain for your Amplify app if needed"
    ssl_certificate = "Amplify automatically provides SSL certificates for custom domains"
  }
}