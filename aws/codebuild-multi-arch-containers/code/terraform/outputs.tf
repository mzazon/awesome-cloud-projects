# Output values for multi-architecture container images with CodeBuild
# These outputs provide important information about the deployed resources

# General Information
output "aws_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Full project name with random suffix"
  value       = local.project_name_full
}

# ECR Repository Information
output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.container_repo.name
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.container_repo.arn
}

output "ecr_repository_uri" {
  description = "URI of the ECR repository"
  value       = aws_ecr_repository.container_repo.repository_url
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.container_repo.repository_url
}

# CodeBuild Project Information
output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.multi_arch_build.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.multi_arch_build.arn
}

output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.arn
}

output "codebuild_service_role_name" {
  description = "Name of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.name
}

# S3 Bucket Information
output "source_bucket_name" {
  description = "Name of the S3 bucket for source code"
  value       = aws_s3_bucket.source_bucket.bucket
}

output "source_bucket_arn" {
  description = "ARN of the S3 bucket for source code"
  value       = aws_s3_bucket.source_bucket.arn
}

output "source_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.source_bucket.bucket_domain_name
}

# CloudWatch Logs Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for CodeBuild"
  value       = aws_cloudwatch_log_group.codebuild_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for CodeBuild"
  value       = aws_cloudwatch_log_group.codebuild_logs.arn
}

# Build Configuration
output "target_platforms" {
  description = "List of target platforms for multi-architecture builds"
  value       = var.target_platforms
}

output "codebuild_compute_type" {
  description = "Compute type used for CodeBuild project"
  value       = var.codebuild_compute_type
}

output "codebuild_image" {
  description = "Docker image used for CodeBuild project"
  value       = var.codebuild_image
}

# Sample Commands for Manual Testing
output "manual_build_command" {
  description = "AWS CLI command to start a manual build"
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.multi_arch_build.name} --region ${data.aws_region.current.name}"
}

output "ecr_login_command" {
  description = "AWS CLI command to login to ECR"
  value       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.container_repo.repository_url}"
}

output "docker_pull_command" {
  description = "Docker command to pull the multi-architecture image"
  value       = "docker pull ${aws_ecr_repository.container_repo.repository_url}:latest"
}

output "docker_inspect_command" {
  description = "Docker command to inspect the multi-architecture manifest"
  value       = "docker buildx imagetools inspect ${aws_ecr_repository.container_repo.repository_url}:latest"
}

# URLs for Console Access
output "codebuild_console_url" {
  description = "URL to access the CodeBuild project in AWS Console"
  value       = "https://console.aws.amazon.com/codesuite/codebuild/${data.aws_region.current.name}/projects/${aws_codebuild_project.multi_arch_build.name}"
}

output "ecr_console_url" {
  description = "URL to access the ECR repository in AWS Console"
  value       = "https://console.aws.amazon.com/ecr/repositories/private/${data.aws_caller_identity.current.account_id}/${aws_ecr_repository.container_repo.name}?region=${data.aws_region.current.name}"
}

output "cloudwatch_logs_url" {
  description = "URL to access CloudWatch logs in AWS Console"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.codebuild_logs.name, "/", "$252F")}"
}

# Verification Commands
output "verify_multi_arch_command" {
  description = "Command to verify multi-architecture support"
  value       = "aws ecr describe-images --repository-name ${aws_ecr_repository.container_repo.name} --region ${data.aws_region.current.name}"
}

output "test_arm64_command" {
  description = "Command to test ARM64 image"
  value       = "docker run --rm --platform linux/arm64 ${aws_ecr_repository.container_repo.repository_url}:latest node -e \"console.log('ARM64:', process.arch)\""
}

output "test_amd64_command" {
  description = "Command to test AMD64 image"
  value       = "docker run --rm --platform linux/amd64 ${aws_ecr_repository.container_repo.repository_url}:latest node -e \"console.log('AMD64:', process.arch)\""
}

# Environment Variables for Local Development
output "environment_variables" {
  description = "Environment variables for local development and testing"
  value = {
    AWS_REGION         = data.aws_region.current.name
    AWS_ACCOUNT_ID     = data.aws_caller_identity.current.account_id
    ECR_REPOSITORY_URI = aws_ecr_repository.container_repo.repository_url
    ECR_REPOSITORY_NAME = aws_ecr_repository.container_repo.name
    CODEBUILD_PROJECT_NAME = aws_codebuild_project.multi_arch_build.name
    S3_BUCKET_NAME = aws_s3_bucket.source_bucket.bucket
  }
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    ecr_repository = {
      name = aws_ecr_repository.container_repo.name
      uri  = aws_ecr_repository.container_repo.repository_url
    }
    codebuild_project = {
      name = aws_codebuild_project.multi_arch_build.name
      arn  = aws_codebuild_project.multi_arch_build.arn
    }
    s3_bucket = {
      name = aws_s3_bucket.source_bucket.bucket
      arn  = aws_s3_bucket.source_bucket.arn
    }
    target_platforms = var.target_platforms
    compute_type     = var.codebuild_compute_type
    environment      = var.environment
  }
}