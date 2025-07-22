# ==========================================
# Core Infrastructure Outputs
# ==========================================

output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# ==========================================
# Security and Encryption Outputs
# ==========================================

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.main.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.main.arn
}

output "kms_alias_name" {
  description = "Alias name for the KMS key"
  value       = aws_kms_alias.main.name
}

# ==========================================
# DynamoDB Outputs
# ==========================================

output "dynamodb_tables" {
  description = "Information about all DynamoDB tables"
  value = {
    tenant = {
      name = aws_dynamodb_table.tenant.name
      arn  = aws_dynamodb_table.tenant.arn
      id   = aws_dynamodb_table.tenant.id
    }
    user = {
      name = aws_dynamodb_table.user.name
      arn  = aws_dynamodb_table.user.arn
      id   = aws_dynamodb_table.user.id
    }
    project = {
      name = aws_dynamodb_table.project.name
      arn  = aws_dynamodb_table.project.arn
      id   = aws_dynamodb_table.project.id
    }
    task = {
      name = aws_dynamodb_table.task.name
      arn  = aws_dynamodb_table.task.arn
      id   = aws_dynamodb_table.task.id
    }
    activity_log = {
      name = aws_dynamodb_table.activity_log.name
      arn  = aws_dynamodb_table.activity_log.arn
      id   = aws_dynamodb_table.activity_log.id
    }
    billing_info = {
      name = aws_dynamodb_table.billing_info.name
      arn  = aws_dynamodb_table.billing_info.arn
      id   = aws_dynamodb_table.billing_info.id
    }
    tenant_usage = {
      name = aws_dynamodb_table.tenant_usage.name
      arn  = aws_dynamodb_table.tenant_usage.arn
      id   = aws_dynamodb_table.tenant_usage.id
    }
  }
}

# Individual table outputs for easy reference
output "tenant_table_name" {
  description = "Name of the tenant DynamoDB table"
  value       = aws_dynamodb_table.tenant.name
}

output "user_table_name" {
  description = "Name of the user DynamoDB table"
  value       = aws_dynamodb_table.user.name
}

output "project_table_name" {
  description = "Name of the project DynamoDB table"
  value       = aws_dynamodb_table.project.name
}

output "task_table_name" {
  description = "Name of the task DynamoDB table"
  value       = aws_dynamodb_table.task.name
}

output "activity_log_table_name" {
  description = "Name of the activity log DynamoDB table"
  value       = aws_dynamodb_table.activity_log.name
}

# ==========================================
# S3 Bucket Outputs
# ==========================================

output "s3_buckets" {
  description = "Information about S3 buckets"
  value = {
    tenant_assets = {
      name = aws_s3_bucket.tenant_assets.bucket
      arn  = aws_s3_bucket.tenant_assets.arn
      id   = aws_s3_bucket.tenant_assets.id
    }
    logs = {
      name = aws_s3_bucket.logs.bucket
      arn  = aws_s3_bucket.logs.arn
      id   = aws_s3_bucket.logs.id
    }
  }
}

output "tenant_assets_bucket_name" {
  description = "Name of the tenant assets S3 bucket"
  value       = aws_s3_bucket.tenant_assets.bucket
}

output "logs_bucket_name" {
  description = "Name of the logs S3 bucket"
  value       = aws_s3_bucket.logs.bucket
}

# ==========================================
# Lambda Function Outputs
# ==========================================

output "lambda_functions" {
  description = "Information about Lambda functions"
  value = {
    tenant_resolver = {
      function_name = aws_lambda_function.tenant_resolver.function_name
      arn          = aws_lambda_function.tenant_resolver.arn
      invoke_arn   = aws_lambda_function.tenant_resolver.invoke_arn
      version      = aws_lambda_function.tenant_resolver.version
    }
    auth_triggers = {
      function_name = aws_lambda_function.auth_triggers.function_name
      arn          = aws_lambda_function.auth_triggers.arn
      invoke_arn   = aws_lambda_function.auth_triggers.invoke_arn
      version      = aws_lambda_function.auth_triggers.version
    }
  }
}

output "tenant_resolver_function_name" {
  description = "Name of the tenant resolver Lambda function"
  value       = aws_lambda_function.tenant_resolver.function_name
}

output "auth_triggers_function_name" {
  description = "Name of the auth triggers Lambda function"
  value       = aws_lambda_function.auth_triggers.function_name
}

# ==========================================
# Cognito Outputs
# ==========================================

output "cognito_user_pool" {
  description = "Cognito User Pool information"
  value = {
    id       = aws_cognito_user_pool.main.id
    arn      = aws_cognito_user_pool.main.arn
    name     = aws_cognito_user_pool.main.name
    endpoint = aws_cognito_user_pool.main.endpoint
    domain   = var.cognito_domain_prefix != null ? aws_cognito_user_pool_domain.main[0].domain : null
  }
}

output "cognito_user_pool_client" {
  description = "Cognito User Pool Client information"
  value = {
    id   = aws_cognito_user_pool_client.main.id
    name = aws_cognito_user_pool_client.main.name
  }
}

output "cognito_identity_pool" {
  description = "Cognito Identity Pool information"
  value = {
    id   = aws_cognito_identity_pool.main.id
    name = aws_cognito_identity_pool.main.identity_pool_name
  }
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_identity_pool_id" {
  description = "ID of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.id
}

output "cognito_user_pool_endpoint" {
  description = "Endpoint for the Cognito User Pool"
  value       = aws_cognito_user_pool.main.endpoint
}

output "cognito_domain" {
  description = "Cognito hosted UI domain (if configured)"
  value       = var.cognito_domain_prefix != null ? aws_cognito_user_pool_domain.main[0].domain : null
}

# ==========================================
# AppSync GraphQL API Outputs
# ==========================================

output "appsync_graphql_api" {
  description = "AppSync GraphQL API information"
  value = {
    id    = aws_appsync_graphql_api.main.id
    name  = aws_appsync_graphql_api.main.name
    arn   = aws_appsync_graphql_api.main.arn
    uris  = aws_appsync_graphql_api.main.uris
  }
}

output "appsync_api_id" {
  description = "ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.id
}

output "appsync_api_url" {
  description = "URL of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

output "appsync_api_endpoint" {
  description = "Endpoint of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

# ==========================================
# IAM Role Outputs
# ==========================================

output "iam_roles" {
  description = "Information about IAM roles"
  value = {
    tenant_resolver_lambda = {
      name = aws_iam_role.tenant_resolver_lambda_role.name
      arn  = aws_iam_role.tenant_resolver_lambda_role.arn
    }
    auth_triggers_lambda = {
      name = aws_iam_role.auth_triggers_lambda_role.name
      arn  = aws_iam_role.auth_triggers_lambda_role.arn
    }
    appsync_service = {
      name = aws_iam_role.appsync_service_role.name
      arn  = aws_iam_role.appsync_service_role.arn
    }
    appsync_cloudwatch = {
      name = aws_iam_role.appsync_cloudwatch_role.name
      arn  = aws_iam_role.appsync_cloudwatch_role.arn
    }
  }
}

# ==========================================
# CloudWatch Outputs
# ==========================================

output "cloudwatch_log_groups" {
  description = "CloudWatch Log Groups"
  value = {
    tenant_resolver = {
      name = aws_cloudwatch_log_group.tenant_resolver.name
      arn  = aws_cloudwatch_log_group.tenant_resolver.arn
    }
    auth_triggers = {
      name = aws_cloudwatch_log_group.auth_triggers.name
      arn  = aws_cloudwatch_log_group.auth_triggers.arn
    }
    appsync = var.enable_appsync_logging ? {
      name = aws_cloudwatch_log_group.appsync[0].name
      arn  = aws_cloudwatch_log_group.appsync[0].arn
    } : null
  }
}

# ==========================================
# Configuration Outputs for Frontend
# ==========================================

output "amplify_configuration" {
  description = "Amplify configuration for frontend applications"
  value = {
    aws_project_region = data.aws_region.current.name
    aws_cognito_region = data.aws_region.current.name
    aws_user_pools_id  = aws_cognito_user_pool.main.id
    aws_user_pools_web_client_id = aws_cognito_user_pool_client.main.id
    aws_cognito_identity_pool_id = aws_cognito_identity_pool.main.id
    aws_appsync_graphqlEndpoint = aws_appsync_graphql_api.main.uris["GRAPHQL"]
    aws_appsync_region = data.aws_region.current.name
    aws_appsync_authenticationType = var.appsync_authentication_type
    oauth = {
      domain = var.cognito_domain_prefix != null ? aws_cognito_user_pool_domain.main[0].domain : null
      scope = [
        "email",
        "openid",
        "profile",
        "aws.cognito.signin.user.admin"
      ]
      redirectSignIn = join(",", var.cognito_callback_urls)
      redirectSignOut = join(",", var.cognito_logout_urls)
      responseType = "code"
    }
  }
  sensitive = false
}

# ==========================================
# Deployment Information
# ==========================================

output "deployment_info" {
  description = "Information about the deployment"
  value = {
    deployed_at = timestamp()
    terraform_version = "~> 1.5"
    aws_provider_version = "~> 5.0"
    resource_suffix = local.suffix
    name_prefix = local.name_prefix
  }
}

# ==========================================
# Security and Compliance Outputs
# ==========================================

output "security_features" {
  description = "Enabled security features"
  value = {
    dynamodb_encryption_enabled = var.enable_dynamodb_encryption
    s3_versioning_enabled = var.enable_s3_versioning
    xray_tracing_enabled = var.enable_xray_tracing
    point_in_time_recovery_enabled = var.enable_point_in_time_recovery
    deletion_protection_enabled = var.enable_deletion_protection
    advanced_security_mode = "ENFORCED"  # Cognito advanced security
    kms_key_rotation_enabled = true
  }
}

# ==========================================
# Cost Optimization Outputs
# ==========================================

output "cost_optimization_features" {
  description = "Enabled cost optimization features"
  value = {
    cost_optimization_enabled = var.enable_cost_optimization
    dynamodb_billing_mode = var.dynamodb_billing_mode
    s3_lifecycle_policies_enabled = var.enable_cost_optimization
    cloudwatch_log_retention_days = var.cloudwatch_log_retention_days
  }
}

# ==========================================
# Multi-Tenant Configuration
# ==========================================

output "tenant_configuration" {
  description = "Multi-tenant configuration settings"
  value = {
    default_tenant_settings = var.default_tenant_settings
    tenant_groups_created = [
      aws_cognito_user_group.super_admins.name,
      aws_cognito_user_group.tenant_admins.name
    ]
  }
  sensitive = false
}

# ==========================================
# Monitoring and Alerting
# ==========================================

output "monitoring_configuration" {
  description = "Monitoring and alerting configuration"
  value = {
    enhanced_monitoring_enabled = var.enable_enhanced_monitoring
    cloudwatch_alarms_created = var.enable_enhanced_monitoring ? [
      "lambda-errors",
      "dynamodb-throttles"
    ] : []
    log_retention_days = var.cloudwatch_log_retention_days
    xray_tracing_enabled = var.enable_xray_tracing
  }
}

# ==========================================
# Quick Reference Commands
# ==========================================

output "useful_commands" {
  description = "Useful AWS CLI commands for managing the infrastructure"
  value = {
    check_cognito_users = "aws cognito-idp list-users --user-pool-id ${aws_cognito_user_pool.main.id}"
    check_dynamodb_tables = "aws dynamodb list-tables --output table"
    check_lambda_functions = "aws lambda list-functions --output table"
    check_appsync_apis = "aws appsync list-graphql-apis --output table"
    view_cloudwatch_logs_tenant_resolver = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.tenant_resolver.name}"
    view_cloudwatch_logs_auth_triggers = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.auth_triggers.name}"
  }
}