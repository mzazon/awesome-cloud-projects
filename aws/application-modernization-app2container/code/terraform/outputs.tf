# Outputs for AWS App2Container Infrastructure
# This file defines all the output values that will be displayed after Terraform deployment

# Core Infrastructure Outputs
output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.app2container.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.app2container.arn
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app2container.name
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.app2container.id
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.app2container.arn
}

# Container Registry Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository for the containerized application"
  value       = aws_ecr_repository.app_repository.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app_repository.name
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.app_repository.arn
}

# Load Balancer Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.app2container.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.app2container.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.app2container.arn
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.app2container.arn
}

output "application_url" {
  description = "URL to access the containerized application"
  value       = "http://${aws_lb.app2container.dns_name}"
}

# CI/CD Pipeline Outputs
output "codecommit_repository_clone_url_http" {
  description = "HTTP clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.app2container.clone_url_http
}

output "codecommit_repository_clone_url_ssh" {
  description = "SSH clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.app2container.clone_url_ssh
}

output "codecommit_repository_name" {
  description = "Name of the CodeCommit repository"
  value       = aws_codecommit_repository.app2container.repository_name
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.app2container.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.app2container.arn
}

output "codepipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.app2container.name
}

output "codepipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.app2container.arn
}

# Storage Outputs
output "app2container_artifacts_bucket" {
  description = "Name of the S3 bucket for App2Container artifacts"
  value       = aws_s3_bucket.app2container_artifacts.bucket
}

output "app2container_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for App2Container artifacts"
  value       = aws_s3_bucket.app2container_artifacts.arn
}

output "codepipeline_artifacts_bucket" {
  description = "Name of the S3 bucket for CodePipeline artifacts"
  value       = aws_s3_bucket.codepipeline_artifacts.bucket
}

output "codepipeline_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for CodePipeline artifacts"
  value       = aws_s3_bucket.codepipeline_artifacts.arn
}

# IAM Role Outputs
output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild service role"
  value       = aws_iam_role.codebuild_role.arn
}

output "codepipeline_role_arn" {
  description = "ARN of the CodePipeline service role"
  value       = aws_iam_role.codepipeline_role.arn
}

# Security Group Outputs
output "ecs_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

# Monitoring and Logging Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for application logs"
  value       = aws_cloudwatch_log_group.app2container.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for application logs"
  value       = aws_cloudwatch_log_group.app2container.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.app2container.dashboard_name}"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

# Auto Scaling Outputs
output "autoscaling_target_resource_id" {
  description = "Resource ID of the auto scaling target"
  value       = aws_appautoscaling_target.ecs_target.resource_id
}

output "autoscaling_policy_arn" {
  description = "ARN of the auto scaling policy"
  value       = aws_appautoscaling_policy.ecs_policy.arn
}

# Network Outputs
output "vpc_id" {
  description = "ID of the VPC where resources are deployed"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "List of subnet IDs where resources are deployed"
  value       = data.aws_subnets.default.ids
}

# Configuration Outputs
output "ssm_parameter_name" {
  description = "Name of the SSM parameter storing environment configuration"
  value       = aws_ssm_parameter.app_config.name
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Resource Naming Outputs
output "name_prefix" {
  description = "Prefix used for all resource names"
  value       = local.name_prefix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
  sensitive   = false
}

# AWS Account Information
output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# Container Configuration Outputs
output "container_port" {
  description = "Port on which the containerized application listens"
  value       = var.container_port
}

output "task_cpu" {
  description = "CPU units allocated to the ECS task"
  value       = var.task_cpu
}

output "task_memory" {
  description = "Memory in MB allocated to the ECS task"
  value       = var.task_memory
}

output "desired_count" {
  description = "Desired number of running tasks"
  value       = var.desired_count
}

# Deployment Information
output "deployment_status" {
  description = "Status information for the deployment"
  value = {
    cluster_name              = aws_ecs_cluster.app2container.name
    service_name             = aws_ecs_service.app2container.name
    task_definition_family   = aws_ecs_task_definition.app2container.family
    task_definition_revision = aws_ecs_task_definition.app2container.revision
    repository_url           = aws_ecr_repository.app_repository.repository_url
    application_url          = "http://${aws_lb.app2container.dns_name}"
    pipeline_name           = aws_codepipeline.app2container.name
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps to complete the App2Container setup"
  value = {
    step_1 = "Push your containerized application image to ECR: ${aws_ecr_repository.app_repository.repository_url}"
    step_2 = "Update the ECS service to use your image by modifying the task definition"
    step_3 = "Configure your CI/CD pipeline by pushing code to: ${aws_codecommit_repository.app2container.clone_url_http}"
    step_4 = "Monitor your application using the CloudWatch dashboard"
    step_5 = "Set up DNS if using a custom domain name"
  }
}

# Cost Optimization Information
output "cost_optimization_recommendations" {
  description = "Recommendations for optimizing costs"
  value = {
    fargate_spot     = "Consider enabling Fargate Spot for development environments"
    right_sizing     = "Monitor CPU and memory utilization to optimize task definitions"
    auto_scaling     = "Auto scaling is configured to scale based on CPU utilization"
    log_retention    = "CloudWatch logs are configured with ${var.log_retention_days} days retention"
    lifecycle_policy = "ECR lifecycle policy configured to manage image retention"
  }
}

# Security Information
output "security_recommendations" {
  description = "Security best practices implemented and recommendations"
  value = {
    encryption      = "S3 buckets and ECR repository have encryption enabled"
    iam_roles      = "Least privilege IAM roles created for all services"
    security_groups = "Security groups configured with minimal required access"
    vpc_placement  = "Resources deployed in VPC with private networking"
    logging        = "Comprehensive logging enabled for audit and monitoring"
    monitoring     = "CloudWatch alarms configured for key metrics"
  }
}

# Troubleshooting Information
output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting the deployment"
  value = {
    check_service_status    = "aws ecs describe-services --cluster ${aws_ecs_cluster.app2container.name} --services ${aws_ecs_service.app2container.name}"
    check_task_logs        = "aws logs tail ${aws_cloudwatch_log_group.app2container.name} --follow"
    check_pipeline_status  = "aws codepipeline get-pipeline-state --name ${aws_codepipeline.app2container.name}"
    check_alb_health       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.app2container.arn}"
    check_cluster_capacity = "aws ecs describe-cluster-capacity --cluster ${aws_ecs_cluster.app2container.name}"
  }
}