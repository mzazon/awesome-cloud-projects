# CodeCommit Repository Information
output "codecommit_repository_name" {
  description = "Name of the CodeCommit repository"
  value       = aws_codecommit_repository.gitops_repo.repository_name
}

output "codecommit_repository_arn" {
  description = "ARN of the CodeCommit repository"
  value       = aws_codecommit_repository.gitops_repo.arn
}

output "codecommit_clone_url_http" {
  description = "HTTPS clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.gitops_repo.clone_url_http
}

output "codecommit_clone_url_ssh" {
  description = "SSH clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.gitops_repo.clone_url_ssh
}

# ECR Repository Information
output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app_repo.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.app_repo.arn
}

# CodeBuild Project Information
output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.gitops_build.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.gitops_build.arn
}

output "codebuild_service_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.arn
}

# ECS Cluster Information
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.gitops_cluster.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.gitops_cluster.arn
}

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.gitops_cluster.id
}

# ECS Task Definition Information
output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.gitops_app.arn
}

output "ecs_task_definition_family" {
  description = "Family of the ECS task definition"
  value       = aws_ecs_task_definition.gitops_app.family
}

output "ecs_task_definition_revision" {
  description = "Revision of the ECS task definition"
  value       = aws_ecs_task_definition.gitops_app.revision
}

# ECS Service Information
output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.gitops_app_service.name
}

output "ecs_service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.gitops_app_service.id
}

# CloudWatch Log Group Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs_logs.arn
}

# Security Group Information
output "ecs_security_group_id" {
  description = "ID of the ECS service security group"
  value       = aws_security_group.ecs_service.id
}

output "ecs_security_group_arn" {
  description = "ARN of the ECS service security group"
  value       = aws_security_group.ecs_service.arn
}

# CloudWatch Events Information
output "cloudwatch_event_rule_name" {
  description = "Name of the CloudWatch Events rule (if enabled)"
  value       = var.enable_codecommit_trigger ? aws_cloudwatch_event_rule.codecommit_trigger[0].name : null
}

output "cloudwatch_event_rule_arn" {
  description = "ARN of the CloudWatch Events rule (if enabled)"
  value       = var.enable_codecommit_trigger ? aws_cloudwatch_event_rule.codecommit_trigger[0].arn : null
}

# Environment Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for unique resource names"
  value       = local.random_suffix
}

# GitOps Workflow Commands
output "git_clone_command" {
  description = "Command to clone the CodeCommit repository"
  value       = "git clone ${aws_codecommit_repository.gitops_repo.clone_url_http}"
}

output "docker_login_command" {
  description = "Command to login to ECR"
  value       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.app_repo.repository_url}"
}

output "codebuild_start_command" {
  description = "Command to manually start a CodeBuild execution"
  value       = "aws codebuild start-build --project-name ${aws_codebuild_project.gitops_build.name}"
}

output "ecs_service_update_command" {
  description = "Command to force ECS service update"
  value       = "aws ecs update-service --cluster ${aws_ecs_cluster.gitops_cluster.name} --service ${aws_ecs_service.gitops_app_service.name} --force-new-deployment"
}

# Application Access Information
output "application_port" {
  description = "Port on which the application is running"
  value       = var.container_port
}

output "container_image_uri" {
  description = "Full URI of the container image"
  value       = "${aws_ecr_repository.app_repo.repository_url}:latest"
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the GitOps workflow"
  value = {
    check_repository = "aws codecommit get-repository --repository-name ${aws_codecommit_repository.gitops_repo.repository_name}"
    check_ecr_images = "aws ecr list-images --repository-name ${aws_ecr_repository.app_repo.name}"
    check_ecs_cluster = "aws ecs describe-clusters --clusters ${aws_ecs_cluster.gitops_cluster.name}"
    check_ecs_service = "aws ecs describe-services --cluster ${aws_ecs_cluster.gitops_cluster.name} --services ${aws_ecs_service.gitops_app_service.name}"
    check_build_project = "aws codebuild batch-get-projects --names ${aws_codebuild_project.gitops_build.name}"
    view_logs = "aws logs describe-log-groups --log-group-name-prefix ${aws_cloudwatch_log_group.ecs_logs.name}"
  }
}