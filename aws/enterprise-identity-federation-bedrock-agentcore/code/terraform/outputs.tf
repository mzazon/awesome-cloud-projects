# ================================================================================
# Outputs for Enterprise Identity Federation with Bedrock AgentCore
# ================================================================================
# This file defines outputs that provide important resource identifiers and 
# endpoints for integration with other systems and for verification purposes.

# ================================================================================
# Cognito User Pool Outputs
# ================================================================================

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool for enterprise identity federation"
  value       = aws_cognito_user_pool.enterprise_pool.id
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool for enterprise identity federation"
  value       = aws_cognito_user_pool.enterprise_pool.arn
}

output "cognito_user_pool_name" {
  description = "Name of the Cognito User Pool"
  value       = aws_cognito_user_pool.enterprise_pool.name
}

output "cognito_user_pool_domain" {
  description = "Domain name for the Cognito User Pool (if configured)"
  value       = aws_cognito_user_pool.enterprise_pool.domain
}

output "cognito_user_pool_client_id" {
  description = "Client ID for the Cognito User Pool App Client"
  value       = aws_cognito_user_pool_client.enterprise_client.id
}

output "cognito_user_pool_client_secret" {
  description = "Client secret for the Cognito User Pool App Client (sensitive)"
  value       = aws_cognito_user_pool_client.enterprise_client.client_secret
  sensitive   = true
}

# ================================================================================
# SAML Identity Provider Outputs
# ================================================================================

output "saml_identity_provider_name" {
  description = "Name of the SAML identity provider configured in Cognito"
  value       = aws_cognito_identity_provider.enterprise_saml.provider_name
}

output "saml_identity_provider_type" {
  description = "Type of the SAML identity provider"
  value       = aws_cognito_identity_provider.enterprise_saml.provider_type
}

# ================================================================================
# Lambda Function Outputs
# ================================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for custom authentication"
  value       = aws_lambda_function.auth_handler.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for custom authentication"
  value       = aws_lambda_function.auth_handler.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch log group name for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ================================================================================
# IAM Outputs
# ================================================================================

output "agentcore_access_policy_arn" {
  description = "ARN of the IAM policy for AgentCore service access"
  value       = aws_iam_policy.agentcore_access_policy.arn
}

output "agentcore_execution_role_arn" {
  description = "ARN of the IAM role for AgentCore AI agents"
  value       = aws_iam_role.agentcore_execution_role.arn
}

output "agentcore_execution_role_name" {
  description = "Name of the IAM role for AgentCore AI agents"
  value       = aws_iam_role.agentcore_execution_role.name
}

# ================================================================================
# Bedrock AgentCore Outputs (Placeholder)
# ================================================================================

# Note: These outputs are placeholders for when Bedrock AgentCore becomes 
# generally available through Terraform

output "agentcore_workload_identity_name" {
  description = "Name of the Bedrock AgentCore workload identity (placeholder)"
  value       = "${var.agentcore_identity_name}-${random_id.suffix.hex}"
}

# output "agentcore_workload_identity_arn" {
#   description = "ARN of the Bedrock AgentCore workload identity"
#   value       = aws_bedrock_agentcore_workload_identity.enterprise_agent.arn
# }

# ================================================================================
# Systems Manager Parameter Store Outputs
# ================================================================================

output "integration_config_parameter_name" {
  description = "Name of the SSM parameter containing integration configuration"
  value       = aws_ssm_parameter.integration_config.name
}

output "integration_config_parameter_arn" {
  description = "ARN of the SSM parameter containing integration configuration"
  value       = aws_ssm_parameter.integration_config.arn
}

# ================================================================================
# Monitoring and Logging Outputs
# ================================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for monitoring"
  value       = aws_cloudwatch_dashboard.enterprise_identity_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.enterprise_identity_dashboard.dashboard_name}"
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail for auditing authentication events"
  value       = aws_cloudtrail.enterprise_identity_audit.name
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail for auditing authentication events"
  value       = aws_cloudtrail.enterprise_identity_audit.arn
}

output "cloudtrail_s3_bucket_name" {
  description = "Name of the S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail_logs.bucket
}

output "cloudtrail_s3_bucket_arn" {
  description = "ARN of the S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail_logs.arn
}

# ================================================================================
# OAuth Configuration Outputs
# ================================================================================

output "oauth_callback_urls" {
  description = "OAuth callback URLs configured for the User Pool App Client"
  value       = aws_cognito_user_pool_client.enterprise_client.callback_urls
}

output "oauth_logout_urls" {
  description = "OAuth logout URLs configured for the User Pool App Client"
  value       = aws_cognito_user_pool_client.enterprise_client.logout_urls
}

output "oauth_scopes" {
  description = "OAuth scopes allowed for the User Pool App Client"
  value       = aws_cognito_user_pool_client.enterprise_client.allowed_oauth_scopes
}

# ================================================================================
# Authentication URLs
# ================================================================================

output "cognito_hosted_ui_url" {
  description = "URL for the Cognito hosted UI (requires domain configuration)"
  value       = "https://${aws_cognito_user_pool.enterprise_pool.name}.auth.${data.aws_region.current.name}.amazoncognito.com/login"
}

output "saml_login_url" {
  description = "SAML login URL for enterprise authentication"
  value       = "https://${aws_cognito_user_pool.enterprise_pool.name}.auth.${data.aws_region.current.name}.amazoncognito.com/saml2/idpresponse"
}

# ================================================================================
# Resource Identifiers
# ================================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

# ================================================================================
# Integration Configuration
# ================================================================================

output "integration_configuration" {
  description = "Complete integration configuration for external systems"
  value = {
    cognito = {
      user_pool_id     = aws_cognito_user_pool.enterprise_pool.id
      app_client_id    = aws_cognito_user_pool_client.enterprise_client.id
      hosted_ui_url    = "https://${aws_cognito_user_pool.enterprise_pool.name}.auth.${data.aws_region.current.name}.amazoncognito.com"
      saml_provider    = aws_cognito_identity_provider.enterprise_saml.provider_name
    }
    lambda = {
      function_name = aws_lambda_function.auth_handler.function_name
      function_arn  = aws_lambda_function.auth_handler.arn
    }
    agentcore = {
      identity_name = "${var.agentcore_identity_name}-${random_id.suffix.hex}"
      execution_role = aws_iam_role.agentcore_execution_role.arn
    }
    monitoring = {
      dashboard_name = aws_cloudwatch_dashboard.enterprise_identity_dashboard.dashboard_name
      cloudtrail_name = aws_cloudtrail.enterprise_identity_audit.name
      log_group_name = aws_cloudwatch_log_group.lambda_logs.name
    }
  }
  sensitive = true
}

# ================================================================================
# Testing and Validation Outputs
# ================================================================================

output "testing_endpoints" {
  description = "Endpoints and identifiers for testing the authentication flow"
  value = {
    user_pool_test_url = "https://${data.aws_region.current.name}.console.aws.amazon.com/cognito/users/?region=${data.aws_region.current.name}#/pool/${aws_cognito_user_pool.enterprise_pool.id}/details"
    lambda_test_url    = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.auth_handler.function_name}"
    cloudwatch_logs_url = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
  }
}

# ================================================================================
# Security Information
# ================================================================================

output "security_configuration" {
  description = "Security configuration summary for compliance reporting"
  value = {
    mfa_enabled               = aws_cognito_user_pool.enterprise_pool.mfa_configuration != "OFF"
    advanced_security_enabled = aws_cognito_user_pool.enterprise_pool.user_pool_add_ons[0].advanced_security_mode == "ENFORCED"
    saml_federation_enabled   = true
    oauth_flows_enabled       = length(aws_cognito_user_pool_client.enterprise_client.allowed_oauth_flows) > 0
    cloudtrail_enabled        = true
    encryption_at_rest        = true
    password_policy = {
      minimum_length    = var.password_minimum_length
      require_uppercase = var.password_require_uppercase
      require_lowercase = var.password_require_lowercase
      require_numbers   = var.password_require_numbers
      require_symbols   = var.password_require_symbols
    }
  }
}