# Outputs for ECS Service Discovery with Route 53 and ALB Infrastructure

# Cluster Information
output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

# Service Discovery Information
output "namespace_name" {
  description = "Name of the Cloud Map private DNS namespace"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

output "namespace_id" {
  description = "ID of the Cloud Map private DNS namespace"
  value       = aws_service_discovery_private_dns_namespace.main.id
}

output "namespace_hosted_zone_id" {
  description = "Route 53 hosted zone ID for the namespace"
  value       = aws_service_discovery_private_dns_namespace.main.hosted_zone
}

output "web_service_discovery_arn" {
  description = "ARN of the web service discovery service"
  value       = aws_service_discovery_service.web.arn
}

output "api_service_discovery_arn" {
  description = "ARN of the API service discovery service"
  value       = aws_service_discovery_service.api.arn
}

output "database_service_discovery_arn" {
  description = "ARN of the database service discovery service"
  value       = aws_service_discovery_service.database.arn
}

# Load Balancer Information
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "api_url" {
  description = "URL for accessing the API service through the load balancer"
  value       = "http://${aws_lb.main.dns_name}/api/"
}

# Target Group Information
output "web_target_group_arn" {
  description = "ARN of the web service target group"
  value       = aws_lb_target_group.web.arn
}

output "api_target_group_arn" {
  description = "ARN of the API service target group"
  value       = aws_lb_target_group.api.arn
}

# Security Group Information
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

# ECS Service Information
output "web_service_name" {
  description = "Name of the web ECS service"
  value       = aws_ecs_service.web.name
}

output "api_service_name" {
  description = "Name of the API ECS service"
  value       = aws_ecs_service.api.name
}

output "web_task_definition_arn" {
  description = "ARN of the web service task definition"
  value       = aws_ecs_task_definition.web.arn
}

output "api_task_definition_arn" {
  description = "ARN of the API service task definition"
  value       = aws_ecs_task_definition.api.arn
}

# IAM Role Information
output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

# VPC and Network Information
output "vpc_id" {
  description = "ID of the VPC used for resources"
  value       = data.aws_vpc.selected.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs used by the ALB"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs used by ECS tasks"
  value       = local.private_subnet_ids
}

# CloudWatch Log Groups
output "web_service_log_group" {
  description = "CloudWatch log group for web service"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.web_service[0].name : null
}

output "api_service_log_group" {
  description = "CloudWatch log group for API service"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.api_service[0].name : null
}

# Service Discovery DNS Names
output "web_service_dns" {
  description = "DNS name for web service discovery"
  value       = "web.${var.namespace_name}"
}

output "api_service_dns" {
  description = "DNS name for API service discovery"
  value       = "api.${var.namespace_name}"
}

output "database_service_dns" {
  description = "DNS name for database service discovery"
  value       = "database.${var.namespace_name}"
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_cluster = "aws ecs describe-clusters --clusters ${aws_ecs_cluster.main.name}"
    check_services = "aws ecs describe-services --cluster ${aws_ecs_cluster.main.name} --services web-service api-service"
    check_target_health = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.web.arn}"
    check_namespace = "aws servicediscovery list-namespaces --filters Name=TYPE,Values=DNS_PRIVATE"
    test_alb = "curl -I http://${aws_lb.main.dns_name}"
    test_api = "curl -I http://${aws_lb.main.dns_name}/api/"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    cluster_name      = aws_ecs_cluster.main.name
    namespace_name    = aws_service_discovery_private_dns_namespace.main.name
    alb_dns_name      = aws_lb.main.dns_name
    web_service_count = var.web_service_desired_count
    api_service_count = var.api_service_desired_count
    environment       = var.environment
    region           = data.aws_region.current.name
  }
}