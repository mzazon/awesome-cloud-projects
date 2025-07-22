# Resource Identifiers
output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.fargate_cluster.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.fargate_cluster.arn
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.fargate_service.name
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.fargate_service.id
}

output "task_definition_family" {
  description = "Family name of the task definition"
  value       = aws_ecs_task_definition.fargate_task.family
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.fargate_task.arn
}

output "task_definition_revision" {
  description = "Revision number of the task definition"
  value       = aws_ecs_task_definition.fargate_task.revision
}

# Load Balancer Information
output "alb_name" {
  description = "Name of the Application Load Balancer"
  value       = aws_lb.fargate_alb.name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.fargate_alb.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.fargate_alb.dns_name
}

output "alb_hosted_zone_id" {
  description = "Hosted zone ID of the Application Load Balancer"
  value       = aws_lb.fargate_alb.zone_id
}

output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.fargate_alb.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.fargate_tg.arn
}

output "target_group_name" {
  description = "Name of the target group"
  value       = aws_lb_target_group.fargate_tg.name
}

# ECR Repository Information
output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.fargate_demo.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.fargate_demo.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.fargate_demo.arn
}

# Security Groups
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "fargate_security_group_id" {
  description = "ID of the Fargate tasks security group"
  value       = aws_security_group.fargate_tasks.id
}

# IAM Roles
output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

# CloudWatch Logs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.fargate_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.fargate_logs.arn
}

# Auto Scaling Information
output "auto_scaling_enabled" {
  description = "Whether auto scaling is enabled"
  value       = var.enable_auto_scaling
}

output "auto_scaling_target_arn" {
  description = "ARN of the auto scaling target"
  value       = var.enable_auto_scaling ? aws_appautoscaling_target.ecs_target[0].arn : null
}

output "cpu_scaling_policy_arn" {
  description = "ARN of the CPU scaling policy"
  value       = var.enable_auto_scaling ? aws_appautoscaling_policy.ecs_cpu_policy[0].arn : null
}

output "memory_scaling_policy_arn" {
  description = "ARN of the memory scaling policy"
  value       = var.enable_auto_scaling ? aws_appautoscaling_policy.ecs_memory_policy[0].arn : null
}

# Network Configuration
output "vpc_id" {
  description = "ID of the VPC"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = local.subnet_ids
}

output "availability_zones" {
  description = "List of availability zones"
  value       = local.availability_zones
}

# Container Configuration
output "container_image" {
  description = "Container image URI"
  value       = local.container_image
}

output "container_port" {
  description = "Container port"
  value       = var.container_port
}

output "container_cpu" {
  description = "Container CPU units"
  value       = var.container_cpu
}

output "container_memory" {
  description = "Container memory in MB"
  value       = var.container_memory
}

# Service Configuration
output "desired_count" {
  description = "Desired number of tasks"
  value       = var.desired_count
}

output "platform_version" {
  description = "Fargate platform version"
  value       = var.platform_version
}

# Useful Commands
output "useful_commands" {
  description = "Useful commands for managing the deployment"
  value = {
    # Docker commands for local development
    ecr_login = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.fargate_demo.repository_url}"
    
    # Container build and push
    build_image = "docker build -t ${aws_ecr_repository.fargate_demo.name} ."
    tag_image   = "docker tag ${aws_ecr_repository.fargate_demo.name}:latest ${aws_ecr_repository.fargate_demo.repository_url}:latest"
    push_image  = "docker push ${aws_ecr_repository.fargate_demo.repository_url}:latest"
    
    # ECS service management
    describe_service = "aws ecs describe-services --cluster ${aws_ecs_cluster.fargate_cluster.name} --services ${aws_ecs_service.fargate_service.name}"
    list_tasks      = "aws ecs list-tasks --cluster ${aws_ecs_cluster.fargate_cluster.name} --service-name ${aws_ecs_service.fargate_service.name}"
    
    # ALB health checks
    check_targets = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.fargate_tg.arn}"
    
    # CloudWatch logs
    view_logs = "aws logs tail /ecs/${aws_ecs_task_definition.fargate_task.family} --follow"
    
    # Auto scaling
    describe_scaling_activities = var.enable_auto_scaling ? "aws application-autoscaling describe-scaling-activities --service-namespace ecs --resource-id service/${aws_ecs_cluster.fargate_cluster.name}/${aws_ecs_service.fargate_service.name}" : "Auto scaling is disabled"
  }
}

# Health Check Endpoints
output "health_check_endpoints" {
  description = "Health check endpoints for the application"
  value = {
    health_check = "http://${aws_lb.fargate_alb.dns_name}${var.health_check_path}"
    main_app     = "http://${aws_lb.fargate_alb.dns_name}/"
    metrics      = "http://${aws_lb.fargate_alb.dns_name}/metrics"
  }
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployment configuration"
  value = {
    environment          = var.environment
    cluster_name         = aws_ecs_cluster.fargate_cluster.name
    service_name         = aws_ecs_service.fargate_service.name
    desired_count        = var.desired_count
    container_cpu        = var.container_cpu
    container_memory     = var.container_memory
    auto_scaling_enabled = var.enable_auto_scaling
    fargate_spot_enabled = var.enable_fargate_spot
    min_capacity         = var.enable_auto_scaling ? var.min_capacity : null
    max_capacity         = var.enable_auto_scaling ? var.max_capacity : null
    alb_internal         = var.alb_internal
    health_check_path    = var.health_check_path
    log_retention_days   = var.log_retention_days
  }
}