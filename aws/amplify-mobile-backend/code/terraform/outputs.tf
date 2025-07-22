# ==============================================================================
# Outputs for Mobile Backend Services with AWS Amplify
# 
# This file defines all the output values that will be displayed after
# the Terraform deployment completes, providing essential information
# for mobile application integration and validation.
# ==============================================================================

# ==============================================================================
# Project Information Outputs
# ==============================================================================

output "project_name" {
  description = "The name of the project with unique suffix"
  value       = local.project_name
}

output "environment" {
  description = "The deployment environment"
  value       = var.environment
}

output "aws_region" {
  description = "The AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "The AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ==============================================================================
# Amazon Cognito Outputs
# ==============================================================================

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool for authentication"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "cognito_user_pool_endpoint" {
  description = "The endpoint URL of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.endpoint
}

output "cognito_user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client for mobile apps"
  value       = aws_cognito_user_pool_client.main.id
  sensitive   = true
}

output "cognito_identity_pool_id" {
  description = "The ID of the Cognito Identity Pool for AWS service access"
  value       = aws_cognito_identity_pool.main.id
}

output "cognito_identity_pool_arn" {
  description = "The ARN of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.arn
}

output "cognito_authenticated_role_arn" {
  description = "The ARN of the IAM role for authenticated users"
  value       = aws_iam_role.cognito_authenticated.arn
}

# ==============================================================================
# AWS AppSync Outputs
# ==============================================================================

output "appsync_graphql_api_id" {
  description = "The ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.id
}

output "appsync_graphql_api_arn" {
  description = "The ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.arn
}

output "appsync_graphql_endpoint" {
  description = "The GraphQL endpoint URL for the AppSync API"
  value       = aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

output "appsync_realtime_endpoint" {
  description = "The real-time endpoint URL for AppSync subscriptions"
  value       = aws_appsync_graphql_api.main.uris["REALTIME"]
}

output "appsync_api_key" {
  description = "The API key for AppSync (if API key authentication is enabled)"
  value       = var.appsync_authentication_type == "API_KEY" ? "API key authentication not configured in this setup" : "Not applicable - using Cognito authentication"
}

# ==============================================================================
# DynamoDB Outputs
# ==============================================================================

output "dynamodb_posts_table_name" {
  description = "The name of the DynamoDB table for posts"
  value       = aws_dynamodb_table.posts.name
}

output "dynamodb_posts_table_arn" {
  description = "The ARN of the DynamoDB table for posts"
  value       = aws_dynamodb_table.posts.arn
}

output "dynamodb_comments_table_name" {
  description = "The name of the DynamoDB table for comments"
  value       = aws_dynamodb_table.comments.name
}

output "dynamodb_comments_table_arn" {
  description = "The ARN of the DynamoDB table for comments"
  value       = aws_dynamodb_table.comments.arn
}

# ==============================================================================
# S3 Storage Outputs
# ==============================================================================

output "s3_user_files_bucket_name" {
  description = "The name of the S3 bucket for user file uploads"
  value       = aws_s3_bucket.user_files.bucket
}

output "s3_user_files_bucket_arn" {
  description = "The ARN of the S3 bucket for user file uploads"
  value       = aws_s3_bucket.user_files.arn
}

output "s3_user_files_bucket_domain_name" {
  description = "The domain name of the S3 bucket"
  value       = aws_s3_bucket.user_files.bucket_domain_name
}

output "s3_user_files_bucket_regional_domain_name" {
  description = "The regional domain name of the S3 bucket"
  value       = aws_s3_bucket.user_files.bucket_regional_domain_name
}

# ==============================================================================
# AWS Lambda Outputs
# ==============================================================================

output "lambda_post_processor_function_name" {
  description = "The name of the Lambda function for post processing"
  value       = aws_lambda_function.post_processor.function_name
}

output "lambda_post_processor_function_arn" {
  description = "The ARN of the Lambda function for post processing"
  value       = aws_lambda_function.post_processor.arn
}

output "lambda_post_processor_invoke_arn" {
  description = "The invoke ARN of the Lambda function for post processing"
  value       = aws_lambda_function.post_processor.invoke_arn
}

# ==============================================================================
# Amazon Pinpoint Outputs
# ==============================================================================

output "pinpoint_application_id" {
  description = "The ID of the Pinpoint application for analytics and push notifications"
  value       = aws_pinpoint_app.main.application_id
}

output "pinpoint_application_arn" {
  description = "The ARN of the Pinpoint application"
  value       = aws_pinpoint_app.main.arn
}

# ==============================================================================
# CloudWatch Monitoring Outputs
# ==============================================================================

output "cloudwatch_dashboard_url" {
  description = "The URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.mobile_backend.dashboard_name}"
}

output "cloudwatch_dashboard_name" {
  description = "The name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.mobile_backend.dashboard_name
}

# ==============================================================================
# Integration Configuration Outputs
# ==============================================================================

output "amplify_configuration" {
  description = "Complete Amplify configuration object for mobile applications"
  value = {
    aws_project_region = data.aws_region.current.name
    aws_cognito_region = data.aws_region.current.name
    
    # Cognito configuration
    aws_user_pools_id                = aws_cognito_user_pool.main.id
    aws_user_pools_web_client_id     = aws_cognito_user_pool_client.main.id
    aws_cognito_identity_pool_id     = aws_cognito_identity_pool.main.id
    
    # AppSync configuration
    aws_appsync_graphqlEndpoint      = aws_appsync_graphql_api.main.uris["GRAPHQL"]
    aws_appsync_region               = data.aws_region.current.name
    aws_appsync_authenticationType   = var.appsync_authentication_type
    aws_appsync_apiKey               = var.appsync_authentication_type == "API_KEY" ? "Configure API key if needed" : null
    
    # S3 configuration
    aws_user_files_s3_bucket         = aws_s3_bucket.user_files.bucket
    aws_user_files_s3_bucket_region  = data.aws_region.current.name
    
    # Pinpoint configuration
    aws_mobile_analytics_app_id      = aws_pinpoint_app.main.application_id
    aws_mobile_analytics_app_region  = data.aws_region.current.name
  }
  sensitive = true
}

# ==============================================================================
# Client SDK Configuration Outputs
# ==============================================================================

output "react_native_config" {
  description = "Configuration object for React Native applications"
  value = {
    Auth = {
      region                = data.aws_region.current.name
      userPoolId           = aws_cognito_user_pool.main.id
      userPoolWebClientId  = aws_cognito_user_pool_client.main.id
      identityPoolId       = aws_cognito_identity_pool.main.id
    }
    API = {
      GraphQL = {
        endpoint    = aws_appsync_graphql_api.main.uris["GRAPHQL"]
        region      = data.aws_region.current.name
        authMode    = var.appsync_authentication_type
      }
    }
    Storage = {
      AWSS3 = {
        bucket = aws_s3_bucket.user_files.bucket
        region = data.aws_region.current.name
      }
    }
    Analytics = {
      Pinpoint = {
        appId  = aws_pinpoint_app.main.application_id
        region = data.aws_region.current.name
      }
    }
  }
  sensitive = true
}

output "ios_config" {
  description = "Configuration object for iOS applications"
  value = {
    CognitoUserPool = {
      Default = {
        PoolId               = aws_cognito_user_pool.main.id
        AppClientId          = aws_cognito_user_pool_client.main.id
        Region               = data.aws_region.current.name
      }
    }
    CognitoIdentityPool = {
      Default = {
        PoolId = aws_cognito_identity_pool.main.id
        Region = data.aws_region.current.name
      }
    }
    AppSync = {
      Default = {
        ApiUrl     = aws_appsync_graphql_api.main.uris["GRAPHQL"]
        Region     = data.aws_region.current.name
        AuthMode   = var.appsync_authentication_type
      }
    }
    S3TransferUtility = {
      Default = {
        Bucket = aws_s3_bucket.user_files.bucket
        Region = data.aws_region.current.name
      }
    }
    PinpointAnalytics = {
      Default = {
        AppId  = aws_pinpoint_app.main.application_id
        Region = data.aws_region.current.name
      }
    }
  }
  sensitive = true
}

output "android_config" {
  description = "Configuration object for Android applications"
  value = {
    CognitoUserPool = {
      Default = {
        PoolId      = aws_cognito_user_pool.main.id
        AppClientId = aws_cognito_user_pool_client.main.id
        Region      = data.aws_region.current.name
      }
    }
    CognitoIdentityPool = {
      Default = {
        PoolId = aws_cognito_identity_pool.main.id
        Region = data.aws_region.current.name
      }
    }
    AppSync = {
      Default = {
        ApiUrl   = aws_appsync_graphql_api.main.uris["GRAPHQL"]
        Region   = data.aws_region.current.name
        AuthMode = var.appsync_authentication_type
      }
    }
    S3TransferUtility = {
      Default = {
        Bucket = aws_s3_bucket.user_files.bucket
        Region = data.aws_region.current.name
      }
    }
    PinpointAnalytics = {
      Default = {
        AppId  = aws_pinpoint_app.main.application_id
        Region = data.aws_region.current.name
      }
    }
  }
  sensitive = true
}

# ==============================================================================
# Validation and Testing Outputs
# ==============================================================================

output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    cognito_user_pool = "aws cognito-idp describe-user-pool --user-pool-id ${aws_cognito_user_pool.main.id}"
    appsync_api       = "aws appsync get-graphql-api --api-id ${aws_appsync_graphql_api.main.id}"
    dynamodb_tables   = "aws dynamodb list-tables --query 'TableNames[?starts_with(@, `${local.project_name}`)]'"
    s3_bucket         = "aws s3api head-bucket --bucket ${aws_s3_bucket.user_files.bucket}"
    lambda_function   = "aws lambda get-function --function-name ${aws_lambda_function.post_processor.function_name}"
    pinpoint_app      = "aws pinpoint get-app --application-id ${aws_pinpoint_app.main.application_id}"
  }
}

# ==============================================================================
# Cost and Resource Summary Outputs
# ==============================================================================

output "deployed_resources_summary" {
  description = "Summary of all deployed resources"
  value = {
    cognito_user_pool     = aws_cognito_user_pool.main.name
    cognito_identity_pool = aws_cognito_identity_pool.main.identity_pool_name
    appsync_api          = aws_appsync_graphql_api.main.name
    dynamodb_tables      = [
      aws_dynamodb_table.posts.name,
      aws_dynamodb_table.comments.name
    ]
    s3_bucket            = aws_s3_bucket.user_files.bucket
    lambda_functions     = [aws_lambda_function.post_processor.function_name]
    pinpoint_application = aws_pinpoint_app.main.name
    iam_roles           = [aws_iam_role.cognito_authenticated.name]
  }
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    note = "Costs are estimates for development workloads and may vary significantly based on usage"
    cognito            = "Free tier: 50,000 MAUs, then $0.0055 per MAU"
    appsync           = "Free tier: 250,000 operations, then $4.00 per million operations"
    dynamodb          = "Pay-per-request: $1.25 per million read/write requests"
    s3_storage        = "$0.023 per GB per month (Standard storage)"
    lambda            = "Free tier: 1M requests/month, then $0.20 per 1M requests"
    pinpoint          = "Free tier: 5,000 targeted users, then $1.00 per 1,000 users"
    cloudwatch        = "Minimal cost for dashboard and basic metrics"
    estimated_total   = "$10-20 per month for typical development usage"
  }
}

# ==============================================================================
# Security Information Outputs
# ==============================================================================

output "security_notes" {
  description = "Important security configuration information"
  value = {
    authentication       = "Cognito User Pool with MFA support configured"
    authorization       = "AppSync uses Cognito User Pool for API authorization"
    data_encryption     = "DynamoDB and S3 use server-side encryption"
    network_security    = "S3 bucket has public access blocked"
    iam_roles          = "Least privilege IAM roles configured for all services"
    monitoring         = "CloudWatch logging enabled for AppSync and Lambda"
    compliance         = "Point-in-time recovery enabled for DynamoDB tables"
  }
}

# ==============================================================================
# Next Steps and Documentation Outputs
# ==============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    mobile_app_integration = "Use the configuration outputs to integrate with your mobile application"
    test_authentication   = "Create test users in Cognito User Pool to validate authentication"
    test_api_operations   = "Test GraphQL operations using the AppSync console"
    upload_test_files     = "Test file upload functionality with the S3 bucket"
    monitor_usage         = "Monitor usage and costs through the CloudWatch dashboard"
    customize_schema      = "Modify the GraphQL schema to match your application requirements"
    add_notifications     = "Configure push notifications in Pinpoint with FCM/APNS credentials"
    implement_cicd        = "Set up CI/CD pipeline for automated deployments"
  }
}