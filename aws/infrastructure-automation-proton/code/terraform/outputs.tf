# outputs.tf - Output values for AWS Proton and CDK infrastructure

# =============================================================================
# Network Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = local.azs
}

# =============================================================================
# Security Group Outputs
# =============================================================================

output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

output "vpc_endpoint_security_group_id" {
  description = "ID of the VPC endpoint security group"
  value       = var.create_vpc_endpoints ? aws_security_group.vpc_endpoint[0].id : null
}

# =============================================================================
# ECS Cluster Outputs
# =============================================================================

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_cluster_capacity_providers" {
  description = "List of capacity providers for the ECS cluster"
  value       = aws_ecs_cluster_capacity_providers.main.capacity_providers
}

# =============================================================================
# S3 Bucket Outputs
# =============================================================================

output "proton_templates_bucket_id" {
  description = "ID of the S3 bucket for Proton templates"
  value       = aws_s3_bucket.proton_templates.id
}

output "proton_templates_bucket_arn" {
  description = "ARN of the S3 bucket for Proton templates"
  value       = aws_s3_bucket.proton_templates.arn
}

output "proton_templates_bucket_name" {
  description = "Name of the S3 bucket for Proton templates"
  value       = aws_s3_bucket.proton_templates.bucket
}

output "proton_templates_bucket_domain_name" {
  description = "Domain name of the S3 bucket for Proton templates"
  value       = aws_s3_bucket.proton_templates.bucket_domain_name
}

# =============================================================================
# IAM Role Outputs
# =============================================================================

output "proton_service_role_arn" {
  description = "ARN of the Proton service role"
  value       = aws_iam_role.proton_service.arn
}

output "proton_service_role_name" {
  description = "Name of the Proton service role"
  value       = aws_iam_role.proton_service.name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.name
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "ecs_task_role_name" {
  description = "Name of the ECS task role"
  value       = aws_iam_role.ecs_task.name
}

# =============================================================================
# Load Balancer Outputs
# =============================================================================

output "alb_id" {
  description = "ID of the Application Load Balancer"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_target_group_arn" {
  description = "ARN of the default target group"
  value       = aws_lb_target_group.default.arn
}

output "alb_listener_arn" {
  description = "ARN of the default listener"
  value       = aws_lb_listener.default.arn
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "ecs_services_log_group_name" {
  description = "Name of the CloudWatch log group for ECS services"
  value       = aws_cloudwatch_log_group.ecs_services.name
}

output "ecs_services_log_group_arn" {
  description = "ARN of the CloudWatch log group for ECS services"
  value       = aws_cloudwatch_log_group.ecs_services.arn
}

output "vpc_flow_logs_log_group_name" {
  description = "Name of the CloudWatch log group for VPC Flow Logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}

output "vpc_flow_logs_log_group_arn" {
  description = "ARN of the CloudWatch log group for VPC Flow Logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].arn : null
}

# =============================================================================
# VPC Endpoints Outputs
# =============================================================================

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 VPC endpoint"
  value       = var.create_vpc_endpoints ? aws_vpc_endpoint.s3[0].id : null
}

output "vpc_endpoint_ecr_api_id" {
  description = "ID of the ECR API VPC endpoint"
  value       = var.create_vpc_endpoints ? aws_vpc_endpoint.ecr_api[0].id : null
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "ID of the ECR DKR VPC endpoint"
  value       = var.create_vpc_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : null
}

output "vpc_endpoint_logs_id" {
  description = "ID of the CloudWatch Logs VPC endpoint"
  value       = var.create_vpc_endpoints ? aws_vpc_endpoint.logs[0].id : null
}

# =============================================================================
# Monitoring Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarms"
  value       = var.enable_cloudwatch_alarms ? aws_sns_topic.alerts[0].arn : null
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarm names"
  value = var.enable_cloudwatch_alarms ? [
    aws_cloudwatch_metric_alarm.ecs_cpu_high[0].alarm_name,
    aws_cloudwatch_metric_alarm.ecs_memory_high[0].alarm_name
  ] : []
}

# =============================================================================
# Configuration Outputs
# =============================================================================

output "region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "name_prefix" {
  description = "Name prefix used for resources"
  value       = local.name_prefix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# =============================================================================
# Service Template Configuration Outputs
# =============================================================================

output "service_template_defaults" {
  description = "Default values for service template configuration"
  value = {
    container_image     = var.default_container_image
    container_port      = var.default_container_port
    memory             = var.default_memory
    cpu                = var.default_cpu
    desired_count      = var.default_desired_count
    min_capacity       = var.default_min_capacity
    max_capacity       = var.default_max_capacity
    health_check_path  = var.default_health_check_path
    cpu_scaling_target = var.cpu_scaling_target
    memory_scaling_target = var.memory_scaling_target
  }
}

# =============================================================================
# Proton Template Configuration Outputs
# =============================================================================

output "proton_template_configuration" {
  description = "Configuration values for Proton templates"
  value = {
    environment_template_name = var.environment_template_name
    service_template_name     = var.service_template_name
    template_bucket_name      = local.template_bucket_name
    log_retention_days        = var.log_retention_days
  }
}

# =============================================================================
# Resource Summary Output
# =============================================================================

output "resource_summary" {
  description = "Summary of key resources created"
  value = {
    vpc_id                      = aws_vpc.main.id
    ecs_cluster_name           = aws_ecs_cluster.main.name
    proton_templates_bucket    = aws_s3_bucket.proton_templates.bucket
    proton_service_role_arn    = aws_iam_role.proton_service.arn
    alb_dns_name               = aws_lb.main.dns_name
    public_subnets             = length(aws_subnet.public)
    private_subnets            = length(aws_subnet.private)
    nat_gateways               = length(aws_nat_gateway.main)
    vpc_endpoints_created      = var.create_vpc_endpoints
    flow_logs_enabled          = var.enable_flow_logs
    container_insights_enabled = var.enable_container_insights
    cloudwatch_alarms_enabled  = var.enable_cloudwatch_alarms
  }
}

# =============================================================================
# Next Steps Output
# =============================================================================

output "next_steps" {
  description = "Next steps to complete the Proton setup"
  value = [
    "1. Create and upload environment template bundle to S3 bucket: ${local.template_bucket_name}",
    "2. Create and upload service template bundle to S3 bucket: ${local.template_bucket_name}",
    "3. Register environment template with Proton using role: ${aws_iam_role.proton_service.arn}",
    "4. Register service template with Proton",
    "5. Create environment using the registered template",
    "6. Deploy service instances to the environment",
    "7. Test the deployed services via ALB: ${aws_lb.main.dns_name}"
  ]
}