# Outputs for Multi-Agent Knowledge Management System
# Provides essential information for system integration and verification

#------------------------------------------------------------------------------
# API GATEWAY OUTPUTS
#------------------------------------------------------------------------------

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint for multi-agent queries"
  value       = aws_apigatewayv2_api.multi_agent_api.api_endpoint
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.multi_agent_api.id
}

output "api_gateway_stage_url" {
  description = "Full URL of the production stage endpoint"
  value       = "${aws_apigatewayv2_api.multi_agent_api.api_endpoint}/prod"
}

output "api_health_check_url" {
  description = "URL for API health check endpoint"
  value       = "${aws_apigatewayv2_api.multi_agent_api.api_endpoint}/prod/health"
}

output "api_query_url" {
  description = "URL for submitting queries to the multi-agent system"
  value       = "${aws_apigatewayv2_api.multi_agent_api.api_endpoint}/prod/query"
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTION OUTPUTS
#------------------------------------------------------------------------------

output "supervisor_agent_function_name" {
  description = "Name of the supervisor agent Lambda function"
  value       = aws_lambda_function.supervisor_agent.function_name
}

output "supervisor_agent_arn" {
  description = "ARN of the supervisor agent Lambda function"
  value       = aws_lambda_function.supervisor_agent.arn
}

output "finance_agent_function_name" {
  description = "Name of the finance agent Lambda function"
  value       = aws_lambda_function.finance_agent.function_name
}

output "finance_agent_arn" {
  description = "ARN of the finance agent Lambda function"
  value       = aws_lambda_function.finance_agent.arn
}

output "hr_agent_function_name" {
  description = "Name of the HR agent Lambda function"
  value       = aws_lambda_function.hr_agent.function_name
}

output "hr_agent_arn" {
  description = "ARN of the HR agent Lambda function"
  value       = aws_lambda_function.hr_agent.arn
}

output "technical_agent_function_name" {
  description = "Name of the technical agent Lambda function"
  value       = aws_lambda_function.technical_agent.function_name
}

output "technical_agent_arn" {
  description = "ARN of the technical agent Lambda function"
  value       = aws_lambda_function.technical_agent.arn
}

output "all_agent_function_names" {
  description = "Map of all agent function names"
  value = {
    supervisor = aws_lambda_function.supervisor_agent.function_name
    finance    = aws_lambda_function.finance_agent.function_name
    hr         = aws_lambda_function.hr_agent.function_name
    technical  = aws_lambda_function.technical_agent.function_name
  }
}

#------------------------------------------------------------------------------
# S3 BUCKET OUTPUTS
#------------------------------------------------------------------------------

output "knowledge_bucket_names" {
  description = "Names of S3 buckets for knowledge domains"
  value = {
    for domain, bucket in aws_s3_bucket.knowledge_buckets :
    domain => bucket.bucket
  }
}

output "knowledge_bucket_arns" {
  description = "ARNs of S3 buckets for knowledge domains"
  value = {
    for domain, bucket in aws_s3_bucket.knowledge_buckets :
    domain => bucket.arn
  }
}

output "finance_bucket_name" {
  description = "Name of the finance knowledge bucket"
  value       = aws_s3_bucket.knowledge_buckets["finance"].bucket
}

output "hr_bucket_name" {
  description = "Name of the HR knowledge bucket"
  value       = aws_s3_bucket.knowledge_buckets["hr"].bucket
}

output "technical_bucket_name" {
  description = "Name of the technical knowledge bucket"
  value       = aws_s3_bucket.knowledge_buckets["technical"].bucket
}

#------------------------------------------------------------------------------
# DYNAMODB OUTPUTS
#------------------------------------------------------------------------------

output "session_table_name" {
  description = "Name of the DynamoDB table for session management"
  value       = aws_dynamodb_table.agent_sessions.name
}

output "session_table_arn" {
  description = "ARN of the DynamoDB table for session management"
  value       = aws_dynamodb_table.agent_sessions.arn
}

output "session_table_stream_arn" {
  description = "ARN of the DynamoDB stream for session monitoring"
  value       = aws_dynamodb_table.agent_sessions.stream_arn
}

#------------------------------------------------------------------------------
# IAM OUTPUTS
#------------------------------------------------------------------------------

output "agent_execution_role_arn" {
  description = "ARN of the IAM role used by agents and Q Business"
  value       = aws_iam_role.agent_execution_role.arn
}

output "agent_execution_role_name" {
  description = "Name of the IAM role used by agents and Q Business"
  value       = aws_iam_role.agent_execution_role.name
}

#------------------------------------------------------------------------------
# Q BUSINESS OUTPUTS (for manual setup)
#------------------------------------------------------------------------------

output "q_business_setup_info" {
  description = "Information for manual Q Business application setup"
  value = {
    application_name    = var.q_business_app_name
    application_description = var.q_business_app_description
    role_arn           = aws_iam_role.agent_execution_role.arn
    data_source_buckets = {
      for domain, bucket in aws_s3_bucket.knowledge_buckets :
      domain => {
        bucket_name = bucket.bucket
        bucket_arn  = bucket.arn
        domain_config = var.knowledge_domains[domain]
      }
    }
    index_configuration = {
      display_name = "Multi-Agent Knowledge Index"
      description  = "Centralized index for multi-agent knowledge retrieval"
    }
  }
}

#------------------------------------------------------------------------------
# CLOUDWATCH OUTPUTS
#------------------------------------------------------------------------------

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names for monitoring and debugging"
  value = {
    supervisor_agent = aws_cloudwatch_log_group.supervisor_agent_logs.name
    finance_agent    = aws_cloudwatch_log_group.finance_agent_logs.name
    hr_agent         = aws_cloudwatch_log_group.hr_agent_logs.name
    technical_agent  = aws_cloudwatch_log_group.technical_agent_logs.name
    api_gateway      = aws_cloudwatch_log_group.api_gateway_logs.name
  }
}

#------------------------------------------------------------------------------
# DEPLOYMENT INFORMATION
#------------------------------------------------------------------------------

output "deployment_info" {
  description = "Key deployment information and next steps"
  value = {
    project_name      = var.project_name
    environment       = var.environment
    random_suffix     = local.name_suffix
    aws_region        = local.region
    aws_account_id    = local.account_id
    deployment_date   = timestamp()
    terraform_version = "~> 1.5.0"
  }
}

#------------------------------------------------------------------------------
# TESTING AND VALIDATION OUTPUTS
#------------------------------------------------------------------------------

output "test_commands" {
  description = "Commands for testing the multi-agent system"
  value = {
    health_check = "curl -X GET ${aws_apigatewayv2_api.multi_agent_api.api_endpoint}/prod/health"
    sample_query = <<-EOT
      curl -X POST ${aws_apigatewayv2_api.multi_agent_api.api_endpoint}/prod/query \
        -H "Content-Type: application/json" \
        -d '{"query": "What is the budget approval process for travel expenses?", "sessionId": "test-session-001"}'
    EOT
    lambda_status_check = <<-EOT
      aws lambda get-function --function-name ${aws_lambda_function.supervisor_agent.function_name} --query 'Configuration.State' --output text
    EOT
  }
}

#------------------------------------------------------------------------------
# SECURITY AND COMPLIANCE OUTPUTS
#------------------------------------------------------------------------------

output "security_configuration" {
  description = "Security features and configurations deployed"
  value = {
    s3_encryption_enabled     = var.enable_encryption
    s3_versioning_enabled     = var.enable_versioning
    s3_public_access_blocked  = true
    dynamodb_encryption       = var.enable_encryption ? "Enabled" : "Disabled"
    api_cors_configured       = true
    iam_least_privilege       = true
    cloudwatch_logging        = true
    session_ttl_hours         = var.session_ttl_hours
  }
}

#------------------------------------------------------------------------------
# COST OPTIMIZATION OUTPUTS
#------------------------------------------------------------------------------

output "cost_optimization_features" {
  description = "Cost optimization features enabled in the deployment"
  value = {
    lambda_pay_per_request     = true
    dynamodb_on_demand_billing = true
    s3_intelligent_tiering     = false # Can be enabled manually if needed
    cloudwatch_log_retention   = "14 days"
    api_gateway_caching        = false # Can be enabled for production
    reserved_capacity          = false # Consider for production workloads
  }
}

#------------------------------------------------------------------------------
# TROUBLESHOOTING OUTPUTS
#------------------------------------------------------------------------------

output "troubleshooting_info" {
  description = "Information for troubleshooting common issues"
  value = {
    common_issues = {
      q_business_setup = "Q Business application must be configured manually after Terraform deployment"
      agent_permissions = "Ensure IAM role has proper permissions for cross-agent Lambda invocation"
      api_cors = "CORS is configured for ${join(", ", var.cors_allowed_origins)}"
      session_cleanup = "Sessions auto-expire after ${var.session_ttl_hours} hours via DynamoDB TTL"
    }
    monitoring_urls = {
      cloudwatch_logs = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#logsV2:log-groups"
      lambda_console = "https://${local.region}.console.aws.amazon.com/lambda/home?region=${local.region}#/functions"
      api_gateway_console = "https://${local.region}.console.aws.amazon.com/apigateway/main/apis/${aws_apigatewayv2_api.multi_agent_api.id}/resources?region=${local.region}"
      dynamodb_console = "https://${local.region}.console.aws.amazon.com/dynamodbv2/home?region=${local.region}#table?name=${aws_dynamodb_table.agent_sessions.name}"
    }
  }
}