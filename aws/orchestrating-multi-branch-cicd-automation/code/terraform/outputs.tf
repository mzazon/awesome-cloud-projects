# Outputs for multi-branch CI/CD pipeline infrastructure
# These outputs provide important information about the deployed resources

# =============================================================================
# REPOSITORY OUTPUTS
# =============================================================================

output "repository_name" {
  description = "Name of the CodeCommit repository"
  value       = aws_codecommit_repository.app_repository.repository_name
}

output "repository_arn" {
  description = "ARN of the CodeCommit repository"
  value       = aws_codecommit_repository.app_repository.arn
}

output "repository_clone_url_http" {
  description = "HTTP clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.app_repository.clone_url_http
}

output "repository_clone_url_ssh" {
  description = "SSH clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.app_repository.clone_url_ssh
}

# =============================================================================
# PIPELINE OUTPUTS
# =============================================================================

output "permanent_pipelines" {
  description = "Information about permanent branch pipelines"
  value = {
    for branch, pipeline in aws_codepipeline.permanent_pipelines : branch => {
      name = pipeline.name
      arn  = pipeline.arn
    }
  }
}

output "main_pipeline_console_url" {
  description = "AWS Console URL for the main pipeline"
  value       = "https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.permanent_pipelines["main"].name}/view"
}

output "develop_pipeline_console_url" {
  description = "AWS Console URL for the develop pipeline"
  value       = length(var.permanent_branches) > 1 ? "https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.permanent_pipelines["develop"].name}/view" : null
}

# =============================================================================
# BUILD OUTPUTS
# =============================================================================

output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.app_build.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.app_build.arn
}

output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.arn
}

output "codebuild_console_url" {
  description = "AWS Console URL for the CodeBuild project"
  value       = "https://console.aws.amazon.com/codesuite/codebuild/projects/${aws_codebuild_project.app_build.name}"
}

# =============================================================================
# LAMBDA OUTPUTS
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda pipeline manager function"
  value       = aws_lambda_function.pipeline_manager.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda pipeline manager function"
  value       = aws_lambda_function.pipeline_manager.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch log group name for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# =============================================================================
# STORAGE OUTPUTS
# =============================================================================

output "artifact_bucket_name" {
  description = "Name of the S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.bucket
}

output "artifact_bucket_arn" {
  description = "ARN of the S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.arn
}

output "artifact_bucket_region" {
  description = "Region of the S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.region
}

# =============================================================================
# IAM OUTPUTS
# =============================================================================

output "codepipeline_role_arn" {
  description = "ARN of the CodePipeline service role"
  value       = aws_iam_role.codepipeline_role.arn
}

output "codepipeline_role_name" {
  description = "Name of the CodePipeline service role"
  value       = aws_iam_role.codepipeline_role.name
}

output "codebuild_role_name" {
  description = "Name of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.name
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for CodeCommit events"
  value       = aws_cloudwatch_event_rule.codecommit_events.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for CodeCommit events"
  value       = aws_cloudwatch_event_rule.codecommit_events.arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.pipeline_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.pipeline_dashboard.dashboard_name}"
}

output "codebuild_log_group_name" {
  description = "CloudWatch log group name for CodeBuild"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.codebuild_logs[0].name : null
}

# =============================================================================
# NOTIFICATION OUTPUTS
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for pipeline notifications"
  value       = var.enable_pipeline_notifications ? aws_sns_topic.pipeline_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for pipeline notifications"
  value       = var.enable_pipeline_notifications ? aws_sns_topic.pipeline_notifications[0].name : null
}

output "pipeline_failure_alarms" {
  description = "CloudWatch alarms for pipeline failures"
  value = var.enable_pipeline_notifications ? {
    for branch in var.permanent_branches : branch => {
      name = aws_cloudwatch_metric_alarm.pipeline_failure_alarm[branch].alarm_name
      arn  = aws_cloudwatch_metric_alarm.pipeline_failure_alarm[branch].arn
    }
  } : {}
}

# =============================================================================
# CONFIGURATION OUTPUTS
# =============================================================================

output "feature_branch_prefix" {
  description = "Prefix for feature branches that trigger pipeline creation"
  value       = var.feature_branch_prefix
}

output "permanent_branches" {
  description = "List of permanent branches with persistent pipelines"
  value       = var.permanent_branches
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# =============================================================================
# RESOURCE IDENTIFIERS
# =============================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "name_prefix" {
  description = "Prefix used for resource naming"
  value       = local.name_prefix
}

# =============================================================================
# USAGE INSTRUCTIONS
# =============================================================================

output "usage_instructions" {
  description = "Instructions for using the multi-branch CI/CD pipeline"
  value = <<-EOT
    Multi-Branch CI/CD Pipeline Setup Complete!
    
    Repository Information:
    - Repository Name: ${aws_codecommit_repository.app_repository.repository_name}
    - Clone URL (HTTP): ${aws_codecommit_repository.app_repository.clone_url_http}
    - Clone URL (SSH): ${aws_codecommit_repository.app_repository.clone_url_ssh}
    
    Pipeline Information:
    - Permanent pipelines created for: ${join(", ", var.permanent_branches)}
    - Feature branches with prefix '${var.feature_branch_prefix}' will automatically get pipelines
    - Lambda function '${aws_lambda_function.pipeline_manager.function_name}' manages pipeline lifecycle
    
    Monitoring:
    - CloudWatch Dashboard: ${aws_cloudwatch_dashboard.pipeline_dashboard.dashboard_name}
    - Build logs: ${var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.codebuild_logs[0].name : "Not enabled"}
    - Lambda logs: ${aws_cloudwatch_log_group.lambda_logs.name}
    
    Next Steps:
    1. Clone the repository using the provided URL
    2. Push code to main/develop branches to trigger permanent pipelines
    3. Create feature branches with '${var.feature_branch_prefix}' prefix for automatic pipeline creation
    4. Monitor pipeline execution through the CloudWatch dashboard
    
    For detailed usage instructions, refer to the original recipe documentation.
  EOT
}

# =============================================================================
# TESTING OUTPUTS
# =============================================================================

output "test_commands" {
  description = "CLI commands for testing the multi-branch pipeline setup"
  value = <<-EOT
    # Test Commands for Multi-Branch CI/CD Pipeline
    
    # 1. List all pipelines
    aws codepipeline list-pipelines --query "pipelines[?contains(name, '${local.repository_name}')]"
    
    # 2. Check Lambda function logs
    aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${aws_lambda_function.pipeline_manager.function_name}"
    
    # 3. Test pipeline execution
    aws codepipeline get-pipeline-state --name "${aws_codepipeline.permanent_pipelines["main"].name}"
    
    # 4. View CodeBuild project details
    aws codebuild batch-get-projects --names "${aws_codebuild_project.app_build.name}"
    
    # 5. Check EventBridge rule
    aws events describe-rule --name "${aws_cloudwatch_event_rule.codecommit_events.name}"
    
    # 6. Test feature branch creation (replace 'feature/test' with your branch name)
    # git checkout -b feature/test
    # git push origin feature/test
    
    # 7. Verify pipeline creation after feature branch push
    aws codepipeline list-pipelines --query "pipelines[?contains(name, 'feature-test')]"
  EOT
}