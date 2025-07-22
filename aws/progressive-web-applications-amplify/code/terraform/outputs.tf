# Outputs for Progressive Web Applications with AWS Amplify

# ================================================================
# COGNITO OUTPUTS - Authentication Information
# ================================================================

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
  description = "Domain of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.domain
}

output "cognito_identity_pool_id" {
  description = "ID of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.id
}

output "cognito_identity_pool_arn" {
  description = "ARN of the Cognito Identity Pool"
  value       = aws_cognito_identity_pool.main.arn
}

# ================================================================
# APPSYNC OUTPUTS - GraphQL API Information
# ================================================================

output "appsync_graphql_api_id" {
  description = "ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.id
}

output "appsync_graphql_api_arn" {
  description = "ARN of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.main.arn
}

output "appsync_graphql_endpoint" {
  description = "GraphQL endpoint URL"
  value       = aws_appsync_graphql_api.main.uris["GRAPHQL"]
}

output "appsync_graphql_realtime_endpoint" {
  description = "GraphQL real-time endpoint URL"
  value       = aws_appsync_graphql_api.main.uris["REALTIME"]
}

output "appsync_api_key" {
  description = "API key for the AppSync GraphQL API (if API key authentication is enabled)"
  value       = var.appsync_authentication_type == "API_KEY" ? aws_appsync_api_key.main[0].key : null
  sensitive   = true
}

# ================================================================
# DYNAMODB OUTPUTS - Database Information
# ================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.tasks.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.tasks.arn
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.tasks.stream_arn
}

output "dynamodb_table_stream_label" {
  description = "Label of the DynamoDB table stream"
  value       = aws_dynamodb_table.tasks.stream_label
}

# ================================================================
# S3 OUTPUTS - Storage Information
# ================================================================

output "s3_bucket_name" {
  description = "Name of the S3 storage bucket"
  value       = aws_s3_bucket.storage.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 storage bucket"
  value       = aws_s3_bucket.storage.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.storage.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.storage.bucket_regional_domain_name
}

# ================================================================
# AMPLIFY OUTPUTS - Frontend Hosting Information
# ================================================================

output "amplify_app_id" {
  description = "ID of the Amplify application"
  value       = aws_amplify_app.main.id
}

output "amplify_app_arn" {
  description = "ARN of the Amplify application"
  value       = aws_amplify_app.main.arn
}

output "amplify_app_name" {
  description = "Name of the Amplify application"
  value       = aws_amplify_app.main.name
}

output "amplify_app_default_domain" {
  description = "Default domain of the Amplify application"
  value       = aws_amplify_app.main.default_domain
}

output "amplify_branch_name" {
  description = "Name of the Amplify branch"
  value       = aws_amplify_branch.main.branch_name
}

output "amplify_branch_url" {
  description = "URL of the Amplify branch"
  value       = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.main.default_domain}"
}

output "amplify_custom_domain" {
  description = "Custom domain of the Amplify application (if configured)"
  value       = var.amplify_domain != "" ? var.amplify_domain : null
}

output "amplify_custom_domain_certificate_arn" {
  description = "ARN of the custom domain certificate"
  value       = var.amplify_domain != "" ? aws_amplify_domain_association.main[0].certificate_arn : null
}

# ================================================================
# IAM OUTPUTS - Role Information
# ================================================================

output "authenticated_role_arn" {
  description = "ARN of the authenticated user role"
  value       = aws_iam_role.authenticated.arn
}

output "unauthenticated_role_arn" {
  description = "ARN of the unauthenticated user role"
  value       = aws_iam_role.unauthenticated.arn
}

output "appsync_service_role_arn" {
  description = "ARN of the AppSync service role"
  value       = aws_iam_role.appsync.arn
}

# ================================================================
# MONITORING OUTPUTS - CloudWatch Information
# ================================================================

output "appsync_log_group_name" {
  description = "Name of the AppSync CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.appsync[0].name : null
}

output "amplify_log_group_name" {
  description = "Name of the Amplify CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.amplify[0].name : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : null
}

# ================================================================
# CONFIGURATION OUTPUTS - Application Configuration
# ================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_id.suffix.hex
}

# ================================================================
# AMPLIFY CONFIGURATION - Client Configuration
# ================================================================

output "amplify_configuration" {
  description = "Complete Amplify configuration for client applications"
  value = {
    aws_project_region                = data.aws_region.current.name
    aws_cognito_identity_pool_id      = aws_cognito_identity_pool.main.id
    aws_cognito_region                = data.aws_region.current.name
    aws_user_pools_id                 = aws_cognito_user_pool.main.id
    aws_user_pools_web_client_id      = aws_cognito_user_pool_client.main.id
    aws_appsync_graphqlEndpoint       = aws_appsync_graphql_api.main.uris["GRAPHQL"]
    aws_appsync_region                = data.aws_region.current.name
    aws_appsync_authenticationType    = var.appsync_authentication_type
    aws_user_files_s3_bucket          = aws_s3_bucket.storage.bucket
    aws_user_files_s3_bucket_region   = data.aws_region.current.name
  }
  sensitive = false
}

# ================================================================
# DEPLOYMENT VERIFICATION - Health Check URLs
# ================================================================

output "deployment_verification" {
  description = "URLs and commands for verifying the deployment"
  value = {
    amplify_app_url          = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.main.default_domain}"
    amplify_console_url      = "https://${data.aws_region.current.name}.console.aws.amazon.com/amplify/home?region=${data.aws_region.current.name}#/${aws_amplify_app.main.id}"
    cognito_console_url      = "https://${data.aws_region.current.name}.console.aws.amazon.com/cognito/users/?region=${data.aws_region.current.name}#/pool/${aws_cognito_user_pool.main.id}"
    appsync_console_url      = "https://${data.aws_region.current.name}.console.aws.amazon.com/appsync/home?region=${data.aws_region.current.name}#/${aws_appsync_graphql_api.main.id}"
    dynamodb_console_url     = "https://${data.aws_region.current.name}.console.aws.amazon.com/dynamodb/home?region=${data.aws_region.current.name}#tables:selected=${aws_dynamodb_table.tasks.name}"
    s3_console_url           = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.storage.bucket}"
    
    # CLI verification commands
    cli_verification_commands = [
      "aws cognito-idp describe-user-pool --user-pool-id ${aws_cognito_user_pool.main.id}",
      "aws appsync get-graphql-api --api-id ${aws_appsync_graphql_api.main.id}",
      "aws dynamodb describe-table --table-name ${aws_dynamodb_table.tasks.name}",
      "aws s3 ls s3://${aws_s3_bucket.storage.bucket}",
      "aws amplify get-app --app-id ${aws_amplify_app.main.id}"
    ]
  }
}

# ================================================================
# COST ESTIMATION - Resource Cost Information
# ================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for resources (USD)"
  value = {
    cognito_user_pool        = "Free tier: 50,000 MAUs, then $0.0055 per MAU"
    appsync_graphql_api      = "Free tier: 250,000 requests/month, then $4.00 per million requests"
    dynamodb_table           = "Free tier: 25 GB storage, 25 RCU/WCU, then pay-per-use"
    s3_storage_bucket        = "Free tier: 5 GB storage, 20,000 GET/2,000 PUT requests"
    amplify_hosting          = "Free tier: 1,000 build minutes, 5 GB storage, 15 GB data transfer"
    cloudwatch_logs          = "Free tier: 5 GB ingestion, 5 GB storage, then $0.50 per GB"
    data_transfer            = "Free tier: 100 GB/month, then $0.09 per GB"
    
    estimated_monthly_cost   = "Development: $0-5, Production: $10-50 (depends on usage)"
    free_tier_coverage       = "Most resources covered by AWS Free Tier for 12 months"
  }
}

# ================================================================
# SECURITY INFORMATION - Security Configuration Details
# ================================================================

output "security_configuration" {
  description = "Security configuration details"
  value = {
    cognito_user_pool_mfa          = "Disabled (configurable)"
    cognito_password_policy        = "8+ chars, uppercase, lowercase, numbers, symbols"
    cognito_advanced_security      = "Enabled"
    s3_public_access_blocked       = "Yes"
    s3_encryption_enabled          = var.enable_s3_encryption
    s3_versioning_enabled          = var.enable_s3_versioning
    dynamodb_encryption_enabled    = "Yes (AWS managed)"
    dynamodb_point_in_time_recovery = "Enabled"
    appsync_authentication_type    = var.appsync_authentication_type
    iam_least_privilege            = "Implemented"
    xray_tracing_enabled           = var.enable_xray_tracing
  }
}

# ================================================================
# NEXT STEPS - Post-Deployment Actions
# ================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Create a test user in Cognito User Pool",
    "2. Test GraphQL API operations using AppSync console",
    "3. Upload test files to S3 bucket to verify storage",
    "4. Configure Amplify application with your source code repository",
    "5. Set up monitoring and alerting for production use",
    "6. Configure custom domain for production deployment",
    "7. Enable MFA for enhanced security",
    "8. Set up CI/CD pipeline for automated deployments",
    "9. Configure backup and disaster recovery procedures",
    "10. Review and optimize costs using AWS Cost Explorer"
  ]
}