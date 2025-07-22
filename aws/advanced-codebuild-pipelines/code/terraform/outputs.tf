# =============================================================================
# RESOURCE IDENTIFIERS
# =============================================================================

output "project_name" {
  description = "The project name used for resource naming"
  value       = var.project_name
}

output "random_suffix" {
  description = "The random suffix used for unique resource names"
  value       = local.random_suffix
}

output "aws_region" {
  description = "The AWS region where resources are deployed"
  value       = local.region
}

output "aws_account_id" {
  description = "The AWS account ID where resources are deployed"
  value       = local.account_id
}

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "cache_bucket_name" {
  description = "Name of the S3 bucket used for build caching"
  value       = aws_s3_bucket.cache_bucket.id
}

output "cache_bucket_arn" {
  description = "ARN of the S3 bucket used for build caching"
  value       = aws_s3_bucket.cache_bucket.arn
}

output "cache_bucket_domain_name" {
  description = "Domain name of the cache bucket"
  value       = aws_s3_bucket.cache_bucket.bucket_domain_name
}

output "artifact_bucket_name" {
  description = "Name of the S3 bucket used for build artifacts"
  value       = aws_s3_bucket.artifact_bucket.id
}

output "artifact_bucket_arn" {
  description = "ARN of the S3 bucket used for build artifacts"
  value       = aws_s3_bucket.artifact_bucket.arn
}

output "artifact_bucket_domain_name" {
  description = "Domain name of the artifact bucket"
  value       = aws_s3_bucket.artifact_bucket.bucket_domain_name
}

# =============================================================================
# ECR REPOSITORY OUTPUTS
# =============================================================================

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app_repository.name
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.app_repository.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app_repository.repository_url
}

output "ecr_registry_id" {
  description = "Registry ID of the ECR repository"
  value       = aws_ecr_repository.app_repository.registry_id
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "codebuild_role_name" {
  description = "Name of the IAM role used by CodeBuild projects"
  value       = aws_iam_role.codebuild_role.name
}

output "codebuild_role_arn" {
  description = "ARN of the IAM role used by CodeBuild projects"
  value       = aws_iam_role.codebuild_role.arn
}

output "lambda_role_name" {
  description = "Name of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_role.arn
}

# =============================================================================
# CODEBUILD PROJECT OUTPUTS
# =============================================================================

output "dependency_build_project_name" {
  description = "Name of the CodeBuild project for dependency management"
  value       = aws_codebuild_project.dependency_build.name
}

output "dependency_build_project_arn" {
  description = "ARN of the CodeBuild project for dependency management"
  value       = aws_codebuild_project.dependency_build.arn
}

output "main_build_project_name" {
  description = "Name of the main CodeBuild project"
  value       = aws_codebuild_project.main_build.name
}

output "main_build_project_arn" {
  description = "ARN of the main CodeBuild project"
  value       = aws_codebuild_project.main_build.arn
}

output "parallel_build_project_name" {
  description = "Name of the CodeBuild project for parallel builds"
  value       = aws_codebuild_project.parallel_build.name
}

output "parallel_build_project_arn" {
  description = "ARN of the CodeBuild project for parallel builds"
  value       = aws_codebuild_project.parallel_build.arn
}

# =============================================================================
# LAMBDA FUNCTION OUTPUTS
# =============================================================================

output "build_orchestrator_function_name" {
  description = "Name of the build orchestrator Lambda function"
  value       = aws_lambda_function.build_orchestrator.function_name
}

output "build_orchestrator_function_arn" {
  description = "ARN of the build orchestrator Lambda function"
  value       = aws_lambda_function.build_orchestrator.arn
}

output "cache_manager_function_name" {
  description = "Name of the cache manager Lambda function"
  value       = aws_lambda_function.cache_manager.function_name
}

output "cache_manager_function_arn" {
  description = "ARN of the cache manager Lambda function"
  value       = aws_lambda_function.cache_manager.arn
}

output "build_analytics_function_name" {
  description = "Name of the build analytics Lambda function"
  value       = aws_lambda_function.build_analytics.function_name
}

output "build_analytics_function_arn" {
  description = "ARN of the build analytics Lambda function"
  value       = aws_lambda_function.build_analytics.arn
}

# =============================================================================
# CLOUDWATCH OUTPUTS
# =============================================================================

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups created for the project"
  value = {
    orchestrator_logs     = aws_cloudwatch_log_group.orchestrator_logs.name
    cache_manager_logs    = aws_cloudwatch_log_group.cache_manager_logs.name
    analytics_logs        = aws_cloudwatch_log_group.analytics_logs.name
    dependency_build_logs = aws_cloudwatch_log_group.dependency_build_logs.name
    main_build_logs       = aws_cloudwatch_log_group.main_build_logs.name
    parallel_build_logs   = aws_cloudwatch_log_group.parallel_build_logs.name
  }
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (if enabled)"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.build_monitoring[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard (if enabled)"
  value = var.enable_cloudwatch_dashboard ? "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.build_monitoring[0].dashboard_name}" : null
}

# =============================================================================
# EVENTBRIDGE OUTPUTS
# =============================================================================

output "eventbridge_rules" {
  description = "EventBridge rules created for automated scheduling"
  value = var.enable_eventbridge_rules ? {
    cache_optimization = aws_cloudwatch_event_rule.cache_optimization[0].name
    build_analytics    = aws_cloudwatch_event_rule.build_analytics[0].name
  } : {}
}

# =============================================================================
# SECURITY GROUP OUTPUTS (if VPC is enabled)
# =============================================================================

output "codebuild_security_group_id" {
  description = "ID of the security group for CodeBuild projects (if VPC is enabled)"
  value       = var.enable_vpc ? aws_security_group.codebuild_sg[0].id : null
}

output "codebuild_security_group_arn" {
  description = "ARN of the security group for CodeBuild projects (if VPC is enabled)"
  value       = var.enable_vpc ? aws_security_group.codebuild_sg[0].arn : null
}

# =============================================================================
# USAGE EXAMPLES AND COMMANDS
# =============================================================================

output "example_build_commands" {
  description = "Example commands to interact with the deployed infrastructure"
  value = {
    # CodeBuild commands
    start_dependency_build = "aws codebuild start-build --project-name ${aws_codebuild_project.dependency_build.name}"
    start_main_build      = "aws codebuild start-build --project-name ${aws_codebuild_project.main_build.name}"
    start_parallel_build  = "aws codebuild start-build --project-name ${aws_codebuild_project.parallel_build.name}"
    
    # Lambda invocation commands
    invoke_orchestrator = "aws lambda invoke --function-name ${aws_lambda_function.build_orchestrator.function_name} --payload '{}' response.json"
    invoke_cache_manager = "aws lambda invoke --function-name ${aws_lambda_function.cache_manager.function_name} --payload '{}' response.json"
    invoke_analytics = "aws lambda invoke --function-name ${aws_lambda_function.build_analytics.function_name} --payload '{}' response.json"
    
    # S3 commands
    list_cache_contents = "aws s3 ls s3://${aws_s3_bucket.cache_bucket.id}/ --recursive"
    list_artifact_contents = "aws s3 ls s3://${aws_s3_bucket.artifact_bucket.id}/ --recursive"
    
    # ECR commands
    get_login_token = "aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app_repository.repository_url}"
    list_images = "aws ecr list-images --repository-name ${aws_ecr_repository.app_repository.name}"
  }
}

output "environment_variables" {
  description = "Environment variables that can be used with the deployed infrastructure"
  value = {
    PROJECT_NAME               = var.project_name
    AWS_REGION                = local.region
    AWS_ACCOUNT_ID            = local.account_id
    CACHE_BUCKET              = aws_s3_bucket.cache_bucket.id
    ARTIFACT_BUCKET           = aws_s3_bucket.artifact_bucket.id
    ECR_REPOSITORY_NAME       = aws_ecr_repository.app_repository.name
    ECR_URI                   = aws_ecr_repository.app_repository.repository_url
    DEPENDENCY_BUILD_PROJECT  = aws_codebuild_project.dependency_build.name
    MAIN_BUILD_PROJECT        = aws_codebuild_project.main_build.name
    PARALLEL_BUILD_PROJECT    = aws_codebuild_project.parallel_build.name
    BUILD_ROLE_ARN            = aws_iam_role.codebuild_role.arn
    ORCHESTRATOR_FUNCTION_NAME = aws_lambda_function.build_orchestrator.function_name
    CACHE_MANAGER_FUNCTION_NAME = aws_lambda_function.cache_manager.function_name
    ANALYTICS_FUNCTION_NAME   = aws_lambda_function.build_analytics.function_name
  }
}

# =============================================================================
# SUMMARY INFORMATION
# =============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    total_codebuild_projects = 3
    total_lambda_functions   = 3
    total_s3_buckets        = 2
    total_ecr_repositories  = 1
    total_iam_roles         = 2
    total_iam_policies      = 2
    vpc_enabled             = var.enable_vpc
    eventbridge_enabled     = var.enable_eventbridge_rules
    dashboard_enabled       = var.enable_cloudwatch_dashboard
    estimated_monthly_cost_usd = "50-200 (varies by usage)"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload source code to the artifact bucket at key '${var.source_key}'",
    "2. Create buildspec files (buildspec-dependencies.yml, buildspec-main.yml, buildspec-parallel.yml) in your source code",
    "3. Test the dependency build project: aws codebuild start-build --project-name ${aws_codebuild_project.dependency_build.name}",
    "4. Monitor builds using the CloudWatch dashboard: https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards",
    "5. Invoke the orchestrator Lambda function to run the complete pipeline",
    "6. Review and customize the EventBridge schedules for automated cache management and analytics",
    "7. Configure your CI/CD system to trigger builds using the CodeBuild projects or Lambda orchestrator"
  ]
}