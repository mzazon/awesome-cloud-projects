# VPC and Networking Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ID of the ECS security group"
  value       = aws_security_group.ecs.id
}

# Load Balancer Outputs
output "dev_alb_dns_name" {
  description = "DNS name of the development ALB"
  value       = aws_lb.dev.dns_name
}

output "dev_alb_zone_id" {
  description = "Zone ID of the development ALB"
  value       = aws_lb.dev.zone_id
}

output "dev_alb_arn" {
  description = "ARN of the development ALB"
  value       = aws_lb.dev.arn
}

output "prod_alb_dns_name" {
  description = "DNS name of the production ALB"
  value       = aws_lb.prod.dns_name
}

output "prod_alb_zone_id" {
  description = "Zone ID of the production ALB"
  value       = aws_lb.prod.zone_id
}

output "prod_alb_arn" {
  description = "ARN of the production ALB"
  value       = aws_lb.prod.arn
}

# Target Group Outputs
output "dev_target_group_arn" {
  description = "ARN of the development target group"
  value       = aws_lb_target_group.dev.arn
}

output "prod_target_group_blue_arn" {
  description = "ARN of the production blue target group"
  value       = aws_lb_target_group.prod_blue.arn
}

output "prod_target_group_green_arn" {
  description = "ARN of the production green target group"
  value       = aws_lb_target_group.prod_green.arn
}

# ECR Repository Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.main.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.main.arn
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.main.name
}

# ECS Cluster Outputs
output "dev_ecs_cluster_id" {
  description = "ID of the development ECS cluster"
  value       = aws_ecs_cluster.dev.id
}

output "dev_ecs_cluster_name" {
  description = "Name of the development ECS cluster"
  value       = aws_ecs_cluster.dev.name
}

output "dev_ecs_cluster_arn" {
  description = "ARN of the development ECS cluster"
  value       = aws_ecs_cluster.dev.arn
}

output "prod_ecs_cluster_id" {
  description = "ID of the production ECS cluster"
  value       = aws_ecs_cluster.prod.id
}

output "prod_ecs_cluster_name" {
  description = "Name of the production ECS cluster"
  value       = aws_ecs_cluster.prod.name
}

output "prod_ecs_cluster_arn" {
  description = "ARN of the production ECS cluster"
  value       = aws_ecs_cluster.prod.arn
}

# ECS Service Outputs
output "dev_ecs_service_name" {
  description = "Name of the development ECS service"
  value       = aws_ecs_service.dev.name
}

output "dev_ecs_service_arn" {
  description = "ARN of the development ECS service"
  value       = aws_ecs_service.dev.id
}

output "prod_ecs_service_name" {
  description = "Name of the production ECS service"
  value       = aws_ecs_service.prod.name
}

output "prod_ecs_service_arn" {
  description = "ARN of the production ECS service"
  value       = aws_ecs_service.prod.id
}

# Task Definition Outputs
output "dev_task_definition_arn" {
  description = "ARN of the development task definition"
  value       = aws_ecs_task_definition.dev.arn
}

output "prod_task_definition_arn" {
  description = "ARN of the production task definition"
  value       = aws_ecs_task_definition.prod.arn
}

# IAM Role Outputs
output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild role"
  value       = aws_iam_role.codebuild.arn
}

output "codepipeline_role_arn" {
  description = "ARN of the CodePipeline role"
  value       = aws_iam_role.codepipeline.arn
}

output "codedeploy_role_arn" {
  description = "ARN of the CodeDeploy role"
  value       = aws_iam_role.codedeploy.arn
}

# S3 Bucket Outputs
output "codepipeline_artifacts_bucket" {
  description = "Name of the CodePipeline artifacts bucket"
  value       = aws_s3_bucket.codepipeline_artifacts.bucket
}

output "codepipeline_artifacts_bucket_arn" {
  description = "ARN of the CodePipeline artifacts bucket"
  value       = aws_s3_bucket.codepipeline_artifacts.arn
}

# CodeBuild Project Outputs
output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.main.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.main.arn
}

# CodePipeline Outputs
output "codepipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.main.name
}

output "codepipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.main.arn
}

# CodeDeploy Outputs
output "codedeploy_application_name" {
  description = "Name of the CodeDeploy application"
  value       = aws_codedeploy_app.main.name
}

output "codedeploy_application_arn" {
  description = "ARN of the CodeDeploy application"
  value       = aws_codedeploy_app.main.arn
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = aws_codedeploy_deployment_group.prod.deployment_group_name
}

# CloudWatch Outputs
output "dev_log_group_name" {
  description = "Name of the development CloudWatch log group"
  value       = aws_cloudwatch_log_group.dev.name
}

output "prod_log_group_name" {
  description = "Name of the production CloudWatch log group"
  value       = aws_cloudwatch_log_group.prod.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.arn
}

output "high_error_rate_alarm_name" {
  description = "Name of the high error rate alarm"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.alarm_name
}

output "high_response_time_alarm_name" {
  description = "Name of the high response time alarm"
  value       = aws_cloudwatch_metric_alarm.high_response_time.alarm_name
}

# Parameter Store Outputs
output "app_version_parameter_name" {
  description = "Name of the app version parameter"
  value       = aws_ssm_parameter.app_version.name
}

output "app_environment_parameter_name" {
  description = "Name of the app environment parameter"
  value       = aws_ssm_parameter.app_environment.name
}

# Application URLs
output "dev_application_url" {
  description = "URL of the development application"
  value       = "http://${aws_lb.dev.dns_name}"
}

output "prod_application_url" {
  description = "URL of the production application"
  value       = "http://${aws_lb.prod.dns_name}"
}

# Deployment Information
output "deployment_instructions" {
  description = "Instructions for deploying applications"
  value = {
    ecr_login_command = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.main.repository_url}"
    build_command     = "docker build -t ${aws_ecr_repository.main.repository_url}:latest ."
    push_command      = "docker push ${aws_ecr_repository.main.repository_url}:latest"
    pipeline_trigger  = "Upload source code to S3 or configure GitHub webhook to trigger pipeline"
  }
}

# Security Information
output "security_groups" {
  description = "Security group information"
  value = {
    alb_security_group_id = aws_security_group.alb.id
    ecs_security_group_id = aws_security_group.ecs.id
  }
}

# Cost Information
output "cost_optimization_notes" {
  description = "Notes about cost optimization"
  value = {
    fargate_spot_enabled = var.enable_fargate_spot
    lifecycle_policies   = var.enable_lifecycle_policies
    log_retention_days   = var.log_retention_days
    dev_log_retention    = var.dev_log_retention_days
  }
}

# Monitoring Information
output "monitoring_endpoints" {
  description = "Monitoring and observability endpoints"
  value = {
    container_insights_enabled = var.enable_container_insights
    xray_enabled               = var.enable_xray
    cloudwatch_logs_dev        = "/aws/ecs/${local.project_name}/dev"
    cloudwatch_logs_prod       = "/aws/ecs/${local.project_name}/prod"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_id                    = aws_vpc.main.id
    public_subnets           = length(aws_subnet.public)
    private_subnets          = length(aws_subnet.private)
    ecs_clusters             = 2
    ecs_services             = 2
    load_balancers           = 2
    target_groups            = 3
    ecr_repositories         = 1
    codebuild_projects       = 1
    codepipeline_pipelines   = 1
    codedeploy_applications  = 1
    sns_topics               = 1
    cloudwatch_alarms        = 2
    iam_roles                = 5
  }
}