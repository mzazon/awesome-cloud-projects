# ============================================================================
# TERRAFORM OUTPUTS FOR ENTERPRISE AUTHENTICATION
# ============================================================================
# This file defines all output values for the enterprise authentication
# solution with AWS Amplify and external identity providers.
#
# Outputs are organized by functional area:
# - Cognito User Pool Information
# - Identity Pool Information  
# - Authentication URLs
# - Application Configuration
# - API Gateway Information
# - Monitoring Resources
# - Security Information
# ============================================================================

# ============================================================================
# COGNITO USER POOL OUTPUTS
# ============================================================================

output "user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_name" {
  description = "Name of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.name
}

output "user_pool_endpoint" {
  description = "Endpoint URL of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.endpoint
}

output "user_pool_creation_date" {
  description = "Creation date of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.creation_date
}

output "user_pool_last_modified_date" {
  description = "Last modified date of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.last_modified_date
}

# ============================================================================
# USER POOL CLIENT OUTPUTS
# ============================================================================

output "user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.web_client.id
}

output "user_pool_client_name" {
  description = "Name of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.web_client.name
}

output "user_pool_client_supported_identity_providers" {
  description = "List of supported identity providers for the User Pool Client"
  value       = aws_cognito_user_pool_client.web_client.supported_identity_providers
}

# ============================================================================
# COGNITO DOMAIN OUTPUTS
# ============================================================================

output "user_pool_domain" {
  description = "Domain name for the Cognito User Pool"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "user_pool_domain_aws_account_id" {
  description = "AWS account ID for the Cognito domain"
  value       = aws_cognito_user_pool_domain.main.aws_account_id
}

output "user_pool_domain_cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN for the Cognito domain"
  value       = aws_cognito_user_pool_domain.main.cloudfront_distribution_arn
}

output "user_pool_domain_s3_bucket" {
  description = "S3 bucket for the Cognito domain"
  value       = aws_cognito_user_pool_domain.main.s3_bucket
}

# ============================================================================
# AUTHENTICATION URLS
# ============================================================================

output "cognito_hosted_ui_url" {
  description = "URL for Cognito Hosted UI login page"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/login?response_type=code&client_id=${aws_cognito_user_pool_client.web_client.id}&redirect_uri=${urlencode(var.callback_urls[0])}"
}

output "cognito_logout_url" {
  description = "URL for Cognito logout"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/logout?client_id=${aws_cognito_user_pool_client.web_client.id}&logout_uri=${urlencode(var.logout_urls[0])}"
}

output "oauth_authorization_endpoint" {
  description = "OAuth 2.0 authorization endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/authorize"
}

output "oauth_token_endpoint" {
  description = "OAuth 2.0 token endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/token"
}

output "oauth_userinfo_endpoint" {
  description = "OAuth 2.0 userinfo endpoint"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/userInfo"
}

output "jwks_uri" {
  description = "JSON Web Key Set URI for token verification"
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
}

# ============================================================================
# IDENTITY POOL OUTPUTS
# ============================================================================

output "identity_pool_id" {
  description = "ID of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.id
}

output "identity_pool_name" {
  description = "Name of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.identity_pool_name
}

output "identity_pool_arn" {
  description = "ARN of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.arn
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "authenticated_role_arn" {
  description = "ARN of the IAM role for authenticated users"
  value       = aws_iam_role.authenticated_user_role.arn
}

output "authenticated_role_name" {
  description = "Name of the IAM role for authenticated users"
  value       = aws_iam_role.authenticated_user_role.name
}

output "unauthenticated_role_arn" {
  description = "ARN of the IAM role for unauthenticated users"
  value       = aws_iam_role.unauthenticated_user_role.arn
}

output "unauthenticated_role_name" {
  description = "Name of the IAM role for unauthenticated users"
  value       = aws_iam_role.unauthenticated_user_role.name
}

# ============================================================================
# IDENTITY PROVIDER OUTPUTS
# ============================================================================

output "saml_provider_name" {
  description = "Name of the SAML identity provider (if enabled)"
  value       = var.enable_saml_provider ? aws_cognito_identity_provider.saml[0].provider_name : null
}

output "saml_provider_type" {
  description = "Type of the SAML identity provider (if enabled)"
  value       = var.enable_saml_provider ? aws_cognito_identity_provider.saml[0].provider_type : null
}

output "oidc_provider_name" {
  description = "Name of the OIDC identity provider (if enabled)"
  value       = var.enable_oidc_provider ? aws_cognito_identity_provider.oidc[0].provider_name : null
}

output "oidc_provider_type" {
  description = "Type of the OIDC identity provider (if enabled)"
  value       = var.enable_oidc_provider ? aws_cognito_identity_provider.oidc[0].provider_type : null
}

# ============================================================================
# S3 STORAGE OUTPUTS
# ============================================================================

output "user_content_bucket_name" {
  description = "Name of the S3 bucket for user content"
  value       = aws_s3_bucket.user_content.bucket
}

output "user_content_bucket_arn" {
  description = "ARN of the S3 bucket for user content"
  value       = aws_s3_bucket.user_content.arn
}

output "user_content_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.user_content.bucket_domain_name
}

output "user_content_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.user_content.region
}

# ============================================================================
# API GATEWAY OUTPUTS
# ============================================================================

output "api_gateway_id" {
  description = "ID of the API Gateway REST API (if created)"
  value       = var.create_api_gateway ? aws_api_gateway_rest_api.main[0].id : null
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API (if created)"
  value       = var.create_api_gateway ? aws_api_gateway_rest_api.main[0].name : null
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway REST API (if created)"
  value       = var.create_api_gateway ? aws_api_gateway_rest_api.main[0].execution_arn : null
}

output "api_gateway_url" {
  description = "URL of the deployed API Gateway (if created)"
  value       = var.create_api_gateway ? "https://${aws_api_gateway_rest_api.main[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}" : null
}

output "api_gateway_stage_name" {
  description = "Stage name of the API Gateway deployment (if created)"
  value       = var.create_api_gateway ? aws_api_gateway_deployment.main[0].stage_name : null
}

output "api_gateway_authorizer_id" {
  description = "ID of the Cognito authorizer for API Gateway (if created)"
  value       = var.create_api_gateway ? aws_api_gateway_authorizer.cognito[0].id : null
}

# ============================================================================
# AWS AMPLIFY OUTPUTS
# ============================================================================

output "amplify_app_id" {
  description = "ID of the Amplify application (if created)"
  value       = var.create_amplify_app ? aws_amplify_app.main[0].id : null
}

output "amplify_app_name" {
  description = "Name of the Amplify application (if created)"
  value       = var.create_amplify_app ? aws_amplify_app.main[0].name : null
}

output "amplify_app_arn" {
  description = "ARN of the Amplify application (if created)"
  value       = var.create_amplify_app ? aws_amplify_app.main[0].arn : null
}

output "amplify_app_default_domain" {
  description = "Default domain of the Amplify application (if created)"
  value       = var.create_amplify_app ? aws_amplify_app.main[0].default_domain : null
}

output "amplify_branch_url" {
  description = "URL of the Amplify branch (if created)"
  value       = var.create_amplify_app ? "https://${var.amplify_branch_name}.${aws_amplify_app.main[0].default_domain}" : null
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for monitoring"
  value       = aws_cloudwatch_log_group.cognito_monitoring.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for monitoring"
  value       = aws_cloudwatch_log_group.cognito_monitoring.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard (if created)"
  value       = var.create_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.monitoring[0].dashboard_name}" : null
}

# ============================================================================
# REACT APPLICATION CONFIGURATION
# ============================================================================

output "react_app_config" {
  description = "Configuration object for React applications using AWS Amplify"
  value = {
    Auth = {
      region                = data.aws_region.current.name
      userPoolId           = aws_cognito_user_pool.main.id
      userPoolWebClientId  = aws_cognito_user_pool_client.web_client.id
      identityPoolId       = aws_cognito_identity_pool.main.id
      oauth = {
        domain                = "${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
        scope                = ["openid", "email", "profile", "aws.cognito.signin.user.admin"]
        redirectSignIn       = var.callback_urls[0]
        redirectSignOut      = var.logout_urls[0]
        responseType         = "code"
      }
    }
    Storage = {
      AWSS3 = {
        bucket = aws_s3_bucket.user_content.bucket
        region = data.aws_region.current.name
      }
    }
    API = var.create_api_gateway ? {
      endpoints = [
        {
          name     = "UserAPI"
          endpoint = "https://${aws_api_gateway_rest_api.main[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}"
          region   = data.aws_region.current.name
        }
      ]
    } : null
  }
}

# ============================================================================
# ENVIRONMENT VARIABLES FOR FRONTEND
# ============================================================================

output "frontend_environment_variables" {
  description = "Environment variables for frontend application deployment"
  value = {
    REACT_APP_AWS_REGION           = data.aws_region.current.name
    REACT_APP_USER_POOL_ID         = aws_cognito_user_pool.main.id
    REACT_APP_USER_POOL_CLIENT_ID  = aws_cognito_user_pool_client.web_client.id
    REACT_APP_IDENTITY_POOL_ID     = aws_cognito_identity_pool.main.id
    REACT_APP_COGNITO_DOMAIN       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
    REACT_APP_S3_BUCKET           = aws_s3_bucket.user_content.bucket
    REACT_APP_API_ENDPOINT        = var.create_api_gateway ? "https://${aws_api_gateway_rest_api.main[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}" : ""
  }
}

# ============================================================================
# SECURITY CONFIGURATION SUMMARY
# ============================================================================

output "security_configuration" {
  description = "Summary of security configurations applied"
  value = {
    advanced_security_mode     = var.advanced_security_mode
    mfa_configuration         = var.mfa_configuration
    enabled_mfas             = var.enabled_mfas
    password_policy = {
      minimum_length     = var.password_minimum_length
      require_lowercase  = var.password_require_lowercase
      require_uppercase  = var.password_require_uppercase
      require_numbers    = var.password_require_numbers
      require_symbols    = var.password_require_symbols
    }
    identity_providers = {
      saml_enabled = var.enable_saml_provider
      oidc_enabled = var.enable_oidc_provider
    }
  }
}

# ============================================================================
# COST ESTIMATION HELPERS
# ============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for different usage levels (USD)"
  value = {
    note = "Costs are estimates and may vary based on actual usage patterns"
    components = {
      cognito_user_pool = {
        description = "Cognito User Pool pricing"
        pricing_model = "Monthly Active Users (MAU)"
        free_tier = "50,000 MAU"
        paid_tier = "$0.0055 per MAU after free tier"
      }
      s3_storage = {
        description = "S3 storage for user content"
        pricing_model = "Per GB stored + requests"
        standard_storage = "$0.023 per GB"
      }
      api_gateway = var.create_api_gateway ? {
        description = "API Gateway REST API"
        pricing_model = "Per million API calls"
        cost = "$3.50 per million requests"
      } : null
      cloudwatch = {
        description = "CloudWatch logs and dashboards"
        pricing_model = "Per GB ingested + storage"
        log_ingestion = "$0.50 per GB"
        log_storage = "$0.03 per GB per month"
      }
    }
  }
}

# ============================================================================
# DEPLOYMENT VERIFICATION
# ============================================================================

output "deployment_verification_steps" {
  description = "Steps to verify successful deployment"
  value = {
    "1_cognito_user_pool" = "aws cognito-idp describe-user-pool --user-pool-id ${aws_cognito_user_pool.main.id}"
    "2_test_hosted_ui" = "Open: https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/login?response_type=code&client_id=${aws_cognito_user_pool_client.web_client.id}&redirect_uri=${urlencode(var.callback_urls[0])}"
    "3_verify_s3_bucket" = "aws s3 ls s3://${aws_s3_bucket.user_content.bucket}/"
    "4_test_api_gateway" = var.create_api_gateway ? "curl -H 'Authorization: Bearer YOUR_TOKEN' https://${aws_api_gateway_rest_api.main[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}/user" : "API Gateway not created"
  }
}

# ============================================================================
# INTEGRATION GUIDANCE
# ============================================================================

output "integration_guidance" {
  description = "Guidance for integrating with external identity providers"
  value = {
    saml_configuration = var.enable_saml_provider ? {
      entity_id = "urn:amazon:cognito:sp:${aws_cognito_user_pool.main.id}"
      reply_url = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/saml2/idpresponse"
      sign_on_url = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/login?response_type=code&client_id=${aws_cognito_user_pool_client.web_client.id}&redirect_uri=${urlencode(var.callback_urls[0])}"
      attribute_mappings = {
        email = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
        given_name = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname"
        family_name = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"
        department = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/department"
      }
    } : "SAML provider not enabled"
    
    oidc_configuration = var.enable_oidc_provider ? {
      issuer = var.oidc_provider_url
      client_id = "Configure in your OIDC provider"
      redirect_uri = var.callback_urls[0]
      scopes = ["openid", "profile", "email"]
    } : "OIDC provider not enabled"
  }
}