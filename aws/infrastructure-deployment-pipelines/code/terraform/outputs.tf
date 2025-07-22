# Repository Information
output "repository_name" {
  description = "Name of the CodeCommit repository"
  value       = aws_codecommit_repository.repo.repository_name
}

output "repository_clone_url_http" {
  description = "HTTP clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.repo.clone_url_http
}

output "repository_clone_url_ssh" {
  description = "SSH clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.repo.clone_url_ssh
}

output "repository_arn" {
  description = "ARN of the CodeCommit repository"
  value       = aws_codecommit_repository.repo.arn
}

# Pipeline Information
output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.pipeline.name
}

output "pipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.pipeline.arn
}

output "pipeline_url" {
  description = "Console URL for the CodePipeline"
  value       = "https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.pipeline.name}/view"
}

# CodeBuild Projects
output "build_project_name" {
  description = "Name of the CodeBuild project for building/synthesizing"
  value       = aws_codebuild_project.build.name
}

output "deploy_dev_project_name" {
  description = "Name of the CodeBuild project for dev deployment"
  value       = aws_codebuild_project.deploy_dev.name
}

output "deploy_prod_project_name" {
  description = "Name of the CodeBuild project for prod deployment"
  value       = aws_codebuild_project.deploy_prod.name
}

# S3 Artifacts Bucket
output "artifacts_bucket_name" {
  description = "Name of the S3 bucket for storing build artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for storing build artifacts"
  value       = aws_s3_bucket.artifacts.arn
}

# IAM Roles
output "codepipeline_role_arn" {
  description = "ARN of the CodePipeline service role"
  value       = aws_iam_role.codepipeline_role.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.arn
}

# SNS Topic (if enabled)
output "notifications_topic_arn" {
  description = "ARN of the SNS topic for pipeline notifications"
  value       = var.enable_notifications ? aws_sns_topic.notifications[0].arn : null
}

# CloudWatch Log Group (if enabled)
output "codebuild_log_group_name" {
  description = "Name of the CloudWatch log group for CodeBuild"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.codebuild[0].name : null
}

# CloudTrail
output "cloudtrail_name" {
  description = "Name of the CloudTrail for audit logging"
  value       = aws_cloudtrail.pipeline_audit.name
}

output "audit_logs_bucket_name" {
  description = "Name of the S3 bucket for CloudTrail audit logs"
  value       = aws_s3_bucket.audit_logs.bucket
}

# Environment Variables for CDK Setup
output "environment_variables" {
  description = "Environment variables for CDK project setup"
  value = {
    AWS_REGION             = local.region
    AWS_ACCOUNT_ID         = local.account_id
    REPOSITORY_NAME        = aws_codecommit_repository.repo.repository_name
    PIPELINE_NAME          = aws_codepipeline.pipeline.name
    ARTIFACTS_BUCKET       = aws_s3_bucket.artifacts.bucket
    CODEBUILD_ROLE_ARN     = aws_iam_role.codebuild_role.arn
    CODEPIPELINE_ROLE_ARN  = aws_iam_role.codepipeline_role.arn
  }
}

# CDK Bootstrap Information
output "cdk_bootstrap_command" {
  description = "CDK bootstrap command for this environment"
  value       = "cdk bootstrap aws://${local.account_id}/${local.region}"
}

# Git Setup Commands
output "git_setup_commands" {
  description = "Commands to set up Git repository"
  value = [
    "git init",
    "git remote add origin ${aws_codecommit_repository.repo.clone_url_http}",
    "git add .",
    "git commit -m 'Initial CDK pipeline setup'",
    "git push -u origin ${var.branch_name}"
  ]
}

# Sample BuildSpec Files
output "sample_buildspec_yml" {
  description = "Sample buildspec.yml for CDK synthesis"
  value = <<-EOF
version: 0.2
phases:
  install:
    runtime-versions:
      nodejs: ${var.nodejs_version}
    commands:
      - echo "Installing CDK CLI"
      - npm install -g aws-cdk
  pre_build:
    commands:
      - echo "Installing dependencies"
      - npm ci
  build:
    commands:
      - echo "Building CDK application"
      - npm run build
      - echo "Synthesizing CDK stacks"
      - cdk synth
artifacts:
  files:
    - '**/*'
  name: BuildArtifacts
EOF
}

output "sample_buildspec_deploy_yml" {
  description = "Sample buildspec-deploy.yml for CDK deployment"
  value = <<-EOF
version: 0.2
phases:
  install:
    runtime-versions:
      nodejs: ${var.nodejs_version}
    commands:
      - echo "Installing CDK CLI"
      - npm install -g aws-cdk
  pre_build:
    commands:
      - echo "Installing dependencies"
      - npm ci
  build:
    commands:
      - echo "Deploying CDK application to $ENVIRONMENT"
      - npm run build
      - cdk deploy --require-approval never --context environment=$ENVIRONMENT
  post_build:
    commands:
      - echo "Deployment completed for $ENVIRONMENT environment"
EOF
}

# Quick Start Guide
output "quick_start_guide" {
  description = "Quick start guide for using this infrastructure"
  value = <<-EOF
# Quick Start Guide for CDK Pipeline

## 1. Clone the repository
git clone ${aws_codecommit_repository.repo.clone_url_http}
cd ${aws_codecommit_repository.repo.repository_name}

## 2. Initialize CDK project
npx cdk init app --language typescript

## 3. Install dependencies
npm install @aws-cdk/pipelines

## 4. Set up environment variables
export AWS_REGION=${local.region}
export AWS_ACCOUNT_ID=${local.account_id}
export REPO_NAME=${aws_codecommit_repository.repo.repository_name}

## 5. Bootstrap CDK
${aws_codecommit_repository.repo.clone_url_http}

## 6. Create buildspec files
# Create buildspec.yml and buildspec-deploy.yml using the sample outputs

## 7. Push your code
git add .
git commit -m "CDK pipeline setup"
git push origin ${var.branch_name}

## 8. Monitor pipeline
# Visit: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.pipeline.name}/view

Pipeline will automatically trigger on commits to the ${var.branch_name} branch.
EOF
}