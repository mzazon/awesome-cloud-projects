# Outputs for Infrastructure Testing Strategy

# Repository information
output "codecommit_repository_name" {
  description = "Name of the created CodeCommit repository"
  value       = aws_codecommit_repository.iac_repo.repository_name
}

output "codecommit_repository_clone_url_http" {
  description = "HTTP clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.iac_repo.clone_url_http
}

output "codecommit_repository_clone_url_ssh" {
  description = "SSH clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.iac_repo.clone_url_ssh
}

output "codecommit_repository_arn" {
  description = "ARN of the CodeCommit repository"
  value       = aws_codecommit_repository.iac_repo.arn
}

# S3 Bucket information
output "artifacts_bucket_name" {
  description = "Name of the S3 bucket for storing artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for storing artifacts"
  value       = aws_s3_bucket.artifacts.arn
}

output "artifacts_bucket_region" {
  description = "Region of the S3 bucket for storing artifacts"
  value       = aws_s3_bucket.artifacts.region
}

# CodeBuild information
output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.iac_testing.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.iac_testing.arn
}

output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.arn
}

# CodePipeline information (conditional)
output "codepipeline_name" {
  description = "Name of the CodePipeline (if enabled)"
  value       = var.enable_pipeline ? aws_codepipeline.iac_testing_pipeline[0].name : null
}

output "codepipeline_arn" {
  description = "ARN of the CodePipeline (if enabled)"
  value       = var.enable_pipeline ? aws_codepipeline.iac_testing_pipeline[0].arn : null
}

output "codepipeline_service_role_arn" {
  description = "ARN of the CodePipeline service role (if enabled)"
  value       = var.enable_pipeline ? aws_iam_role.codepipeline_role[0].arn : null
}

# CloudWatch Logs information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for CodeBuild"
  value       = aws_cloudwatch_log_group.codebuild_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for CodeBuild"
  value       = aws_cloudwatch_log_group.codebuild_logs.arn
}

# Notification information (conditional)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if configured)"
  value       = var.notification_email != null ? aws_sns_topic.build_notifications[0].arn : null
}

output "notification_email" {
  description = "Email address configured for notifications (if set)"
  value       = var.notification_email
  sensitive   = true
}

# Project information
output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region used for deployment"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS Account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

# Random suffix for troubleshooting
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Quick start commands
output "setup_commands" {
  description = "Commands to set up the testing environment"
  value = {
    clone_repository = "git clone ${aws_codecommit_repository.iac_repo.clone_url_http}"
    start_build      = "aws codebuild start-build --project-name ${aws_codebuild_project.iac_testing.name}"
    view_logs        = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.codebuild_logs.name}"
    start_pipeline   = var.enable_pipeline ? "aws codepipeline start-pipeline-execution --name ${aws_codepipeline.iac_testing_pipeline[0].name}" : "Pipeline not enabled"
  }
}

# Testing tools configuration
output "configured_testing_tools" {
  description = "List of testing tools configured in the environment"
  value       = var.testing_tools
}

# Sample buildspec content for reference
output "sample_buildspec_content" {
  description = "Sample buildspec.yml content for the testing pipeline"
  value = <<-EOT
    version: 0.2

    phases:
      install:
        runtime-versions:
          python: 3.9
        commands:
          - echo "Installing dependencies..."
          - pip install -r tests/requirements.txt
          - pip install awscli

      pre_build:
        commands:
          - echo "Pre-build phase started on `date`"
          - echo "Validating AWS credentials..."
          - aws sts get-caller-identity

      build:
        commands:
          - echo "Build phase started on `date`"
          - echo "Running unit tests..."
          - cd tests && python -m pytest test_s3_bucket.py -v
          - cd ..
          - echo "Running security tests..."
          - python tests/security_test.py
          - echo "Running cost analysis..."
          - python tests/cost_analysis.py
          - echo "Running integration tests..."
          - python tests/integration_test.py

      post_build:
        commands:
          - echo "Post-build phase started on `date`"
          - echo "All tests completed successfully!"

    artifacts:
      files:
        - "**/*"
      base-directory: .
  EOT
}

# Cost estimation information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the infrastructure"
  value = {
    codebuild_small   = "~$5-15/month (depends on build frequency)"
    codepipeline      = "~$1/month per active pipeline"
    s3_storage        = "~$1-5/month (depends on artifact storage)"
    cloudwatch_logs   = "~$1-3/month (depends on log volume)"
    total_estimate    = "~$8-24/month"
    note             = "Costs vary based on usage patterns and build frequency"
  }
}

# Security and compliance outputs
output "security_features" {
  description = "Security features enabled in the infrastructure"
  value = {
    s3_encryption                = var.artifact_encryption ? "Enabled" : "Disabled"
    s3_public_access_blocked     = "Enabled"
    s3_versioning                = "Enabled"
    iam_least_privilege          = "Enabled"
    cloudwatch_logging           = "Enabled"
    integration_test_isolation   = "Enabled (limited scope permissions)"
  }
}