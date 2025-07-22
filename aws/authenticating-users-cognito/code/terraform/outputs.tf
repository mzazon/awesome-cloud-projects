# Outputs for Cognito User Pool Authentication Infrastructure
# This file defines outputs that provide essential information for application integration

# User Pool Outputs
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
  description = "Endpoint name of the user pool"
  value       = aws_cognito_user_pool.main.endpoint
}

# User Pool Client Outputs
output "user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "user_pool_client_secret" {
  description = "Secret of the Cognito User Pool Client (if generated)"
  value       = var.generate_secret ? aws_cognito_user_pool_client.main.client_secret : null
  sensitive   = true
}

output "user_pool_client_name" {
  description = "Name of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.name
}

# Hosted UI Outputs
output "hosted_ui_domain" {
  description = "Domain name for the Cognito hosted UI"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "hosted_ui_url" {
  description = "Full URL for the Cognito hosted UI"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "login_url" {
  description = "Login URL for the hosted UI with proper parameters"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.main.id}&response_type=code&scope=openid+email+profile&redirect_uri=${var.callback_urls[0]}"
}

output "logout_url" {
  description = "Logout URL for the hosted UI with proper parameters"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/logout?client_id=${aws_cognito_user_pool_client.main.id}&logout_uri=${var.logout_urls[0]}"
}

# OAuth and OIDC Endpoints
output "oauth_endpoints" {
  description = "OAuth 2.0 and OpenID Connect endpoints"
  value = {
    authorization_endpoint = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/authorize"
    token_endpoint        = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/token"
    userinfo_endpoint     = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/userInfo"
    jwks_uri             = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
    issuer               = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

# User Groups Outputs
output "user_groups" {
  description = "Information about created user groups"
  value = {
    administrators = {
      name        = aws_cognito_user_group.administrators.name
      description = aws_cognito_user_group.administrators.description
      precedence  = aws_cognito_user_group.administrators.precedence
    }
    customers = {
      name        = aws_cognito_user_group.customers.name
      description = aws_cognito_user_group.customers.description
      precedence  = aws_cognito_user_group.customers.precedence
    }
    premium_customers = {
      name        = aws_cognito_user_group.premium_customers.name
      description = aws_cognito_user_group.premium_customers.description
      precedence  = aws_cognito_user_group.premium_customers.precedence
    }
  }
}

# Security Configuration Outputs
output "security_configuration" {
  description = "Security configuration details"
  value = {
    mfa_configuration      = aws_cognito_user_pool.main.mfa_configuration
    advanced_security_mode = var.advanced_security_mode
    password_policy = {
      minimum_length                   = var.password_minimum_length
      require_uppercase                = var.password_require_uppercase
      require_lowercase                = var.password_require_lowercase
      require_numbers                  = var.password_require_numbers
      require_symbols                  = var.password_require_symbols
      temporary_password_validity_days = var.temporary_password_validity_days
    }
  }
}

# Token Configuration Outputs
output "token_configuration" {
  description = "Token validity and configuration details"
  value = {
    access_token_validity  = var.access_token_validity
    id_token_validity     = var.id_token_validity
    refresh_token_validity = var.refresh_token_validity
    token_validity_units = {
      access_token  = "minutes"
      id_token      = "minutes"
      refresh_token = "days"
    }
  }
}

# Application Configuration Output (JSON format for easy integration)
output "application_config" {
  description = "Complete configuration for application integration (JSON format)"
  value = jsonencode({
    userPoolId     = aws_cognito_user_pool.main.id
    userPoolArn    = aws_cognito_user_pool.main.arn
    clientId       = aws_cognito_user_pool_client.main.id
    clientSecret   = var.generate_secret ? aws_cognito_user_pool_client.main.client_secret : null
    region         = data.aws_region.current.name
    hostedUIUrl    = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
    loginUrl       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.main.id}&response_type=code&scope=openid+email+profile&redirect_uri=${var.callback_urls[0]}"
    logoutUrl      = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/logout?client_id=${aws_cognito_user_pool_client.main.id}&logout_uri=${var.logout_urls[0]}"
    oauth = {
      domain              = "${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
      scope               = ["openid", "email", "profile"]
      redirectSignIn      = var.callback_urls[0]
      redirectSignOut     = var.logout_urls[0]
      responseType        = "code"
    }
    endpoints = {
      authorization = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/authorize"
      token        = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/token"
      userinfo     = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/oauth2/userInfo"
      jwks         = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
      issuer       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}"
    }
  })
  sensitive = true
}

# IAM Role Outputs
output "sns_role_arn" {
  description = "ARN of the IAM role used by Cognito for SMS delivery"
  value       = aws_iam_role.cognito_sns_role.arn
}

# Google Identity Provider Outputs (if enabled)
output "google_identity_provider" {
  description = "Google identity provider configuration (if enabled)"
  value = var.enable_google_identity_provider && var.google_client_id != null && var.google_client_secret != null ? {
    provider_name = aws_cognito_identity_provider.google[0].provider_name
    provider_type = aws_cognito_identity_provider.google[0].provider_type
  } : null
}

# Test Users Outputs (if created)
output "test_users" {
  description = "Information about created test users (if enabled)"
  value = var.create_test_users ? {
    admin_user = {
      username = aws_cognito_user.admin[0].username
      email    = var.admin_email
      group    = aws_cognito_user_group.administrators.name
    }
    customer_user = {
      username = aws_cognito_user.customer[0].username
      email    = var.customer_email
      group    = aws_cognito_user_group.customers.name
    }
  } : null
}

# Resource Tags Output
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Validation Testing Information
output "validation_info" {
  description = "Information for validating the Cognito setup"
  value = {
    test_login_url = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.main.id}&response_type=code&scope=openid+email+profile&redirect_uri=${var.callback_urls[0]}"
    cli_test_commands = {
      describe_user_pool = "aws cognito-idp describe-user-pool --user-pool-id ${aws_cognito_user_pool.main.id}"
      list_users        = "aws cognito-idp list-users --user-pool-id ${aws_cognito_user_pool.main.id}"
      list_groups       = "aws cognito-idp list-groups --user-pool-id ${aws_cognito_user_pool.main.id}"
    }
  }
}