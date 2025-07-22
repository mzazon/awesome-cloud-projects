# ===============================================================================
# ECS Cluster Outputs
# ===============================================================================

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

# ===============================================================================
# ECR Repository Outputs
# ===============================================================================

output "ecr_repository_url" {
  description = "URL of the ECR repository"
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

output "ecr_repository_registry_id" {
  description = "Registry ID of the ECR repository"
  value       = aws_ecr_repository.app_repository.registry_id
}

# ===============================================================================
# ECS Service Outputs
# ===============================================================================

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "ecs_service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.app.id
}

output "ecs_service_cluster" {
  description = "Cluster name where the service is running"
  value       = aws_ecs_service.app.cluster
}

output "ecs_service_desired_count" {
  description = "Desired number of tasks for the service"
  value       = aws_ecs_service.app.desired_count
}

# ===============================================================================
# ECS Task Definition Outputs
# ===============================================================================

output "ecs_task_definition_family" {
  description = "Family name of the ECS task definition"
  value       = aws_ecs_task_definition.app.family
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.app.arn
}

output "ecs_task_definition_revision" {
  description = "Revision of the ECS task definition"
  value       = aws_ecs_task_definition.app.revision
}

# ===============================================================================
# IAM Role Outputs
# ===============================================================================

output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "ecs_execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.ecs_execution_role.name
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "ecs_task_role_name" {
  description = "Name of the ECS task role"
  value       = aws_iam_role.ecs_task_role.name
}

# ===============================================================================
# Security Group Outputs
# ===============================================================================

output "security_group_id" {
  description = "ID of the security group for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "security_group_arn" {
  description = "ARN of the security group for ECS tasks"
  value       = aws_security_group.ecs_tasks.arn
}

output "security_group_name" {
  description = "Name of the security group for ECS tasks"
  value       = aws_security_group.ecs_tasks.name
}

# ===============================================================================
# CloudWatch Log Group Outputs
# ===============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs_log_group.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs_log_group.arn
}

# ===============================================================================
# Auto Scaling Outputs
# ===============================================================================

output "autoscaling_target_resource_id" {
  description = "Resource ID of the auto scaling target"
  value       = aws_appautoscaling_target.ecs_target.resource_id
}

output "autoscaling_policy_name" {
  description = "Name of the auto scaling policy"
  value       = aws_appautoscaling_policy.ecs_cpu_policy.name
}

output "autoscaling_policy_arn" {
  description = "ARN of the auto scaling policy"
  value       = aws_appautoscaling_policy.ecs_cpu_policy.arn
}

# ===============================================================================
# Network Configuration Outputs
# ===============================================================================

output "vpc_id" {
  description = "ID of the VPC used for the ECS service"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for the ECS service"
  value       = local.subnet_ids
}

# ===============================================================================
# Random Values Outputs
# ===============================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_password.suffix.result
}

# ===============================================================================
# Deployment Information
# ===============================================================================

output "deployment_info" {
  description = "Information for deploying and managing the Fargate service"
  value = {
    cluster_name              = aws_ecs_cluster.main.name
    service_name              = aws_ecs_service.app.name
    task_definition_family    = aws_ecs_task_definition.app.family
    ecr_repository_url        = aws_ecr_repository.app_repository.repository_url
    log_group_name           = aws_cloudwatch_log_group.ecs_log_group.name
    autoscaling_min_capacity = var.min_capacity
    autoscaling_max_capacity = var.max_capacity
    container_port           = var.container_port
  }
}

# ===============================================================================
# Docker Build Commands
# ===============================================================================

output "docker_build_commands" {
  description = "Commands to build and push Docker image to ECR"
  value = {
    ecr_login = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.app_repository.repository_url}"
    
    docker_build = "docker build -t ${aws_ecr_repository.app_repository.name} ."
    
    docker_tag = "docker tag ${aws_ecr_repository.app_repository.name}:latest ${aws_ecr_repository.app_repository.repository_url}:latest"
    
    docker_push = "docker push ${aws_ecr_repository.app_repository.repository_url}:latest"
    
    update_service = "aws ecs update-service --cluster ${aws_ecs_cluster.main.name} --service ${aws_ecs_service.app.name} --force-new-deployment"
  }
}

# ===============================================================================
# Monitoring and Debugging Commands
# ===============================================================================

output "useful_commands" {
  description = "Useful AWS CLI commands for monitoring and debugging"
  value = {
    check_service_status = "aws ecs describe-services --cluster ${aws_ecs_cluster.main.name} --services ${aws_ecs_service.app.name}"
    
    list_running_tasks = "aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.app.name}"
    
    view_logs = "aws logs tail ${aws_cloudwatch_log_group.ecs_log_group.name} --follow"
    
    describe_tasks = "aws ecs describe-tasks --cluster ${aws_ecs_cluster.main.name} --tasks $(aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.app.name} --query 'taskArns[0]' --output text)"
    
    exec_into_task = "aws ecs execute-command --cluster ${aws_ecs_cluster.main.name} --task TASK_ARN --container ${var.project_name}-container --interactive --command '/bin/sh'"
  }
}