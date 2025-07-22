# Output values for the distributed session management infrastructure
# These outputs provide important information about deployed resources

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

# MemoryDB Outputs
output "memorydb_cluster_id" {
  description = "ID of the MemoryDB cluster"
  value       = aws_memorydb_cluster.session_store.id
}

output "memorydb_cluster_endpoint" {
  description = "Primary endpoint for the MemoryDB cluster"
  value       = aws_memorydb_cluster.session_store.cluster_endpoint[0].address
}

output "memorydb_cluster_port" {
  description = "Port for the MemoryDB cluster"
  value       = aws_memorydb_cluster.session_store.cluster_endpoint[0].port
}

output "memorydb_cluster_arn" {
  description = "ARN of the MemoryDB cluster"
  value       = aws_memorydb_cluster.session_store.arn
}

output "memorydb_parameter_group_name" {
  description = "Name of the MemoryDB parameter group"
  value       = aws_memorydb_cluster.session_store.parameter_group_name
}

# Application Load Balancer Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_url" {
  description = "URL of the Application Load Balancer"
  value       = "http://${aws_lb.main.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.ecs_tasks.arn
}

# ECS Outputs
output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.session_app.name
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.session_app.arn
}

output "ecs_service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.session_app.id
}

# IAM Outputs
output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ID of the ECS security group"
  value       = aws_security_group.ecs_tasks.id
}

output "memorydb_security_group_id" {
  description = "ID of the MemoryDB security group"
  value       = aws_security_group.memorydb.id
}

# Systems Manager Parameter Store Outputs
output "parameter_store_paths" {
  description = "Paths to Systems Manager parameters"
  value = {
    memorydb_endpoint   = aws_ssm_parameter.memorydb_endpoint.name
    memorydb_port      = aws_ssm_parameter.memorydb_port.name
    session_timeout    = aws_ssm_parameter.session_timeout.name
    redis_database     = aws_ssm_parameter.redis_database.name
  }
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs_logs.arn
}

# Auto Scaling Outputs
output "autoscaling_target_arn" {
  description = "ARN of the auto scaling target"
  value       = aws_appautoscaling_target.ecs_target.resource_id
}

output "autoscaling_policy_arn" {
  description = "ARN of the auto scaling policy"
  value       = aws_appautoscaling_policy.ecs_cpu_policy.arn
}

# Connection Information for Applications
output "redis_connection_string" {
  description = "Redis connection string for applications (sensitive)"
  value       = "redis://${aws_memorydb_cluster.session_store.cluster_endpoint[0].address}:${aws_memorydb_cluster.session_store.cluster_endpoint[0].port}"
  sensitive   = true
}

output "session_configuration" {
  description = "Session configuration summary"
  value = {
    timeout_seconds    = var.session_timeout_seconds
    redis_database    = var.redis_database_number
    endpoint          = aws_memorydb_cluster.session_store.cluster_endpoint[0].address
    port             = aws_memorydb_cluster.session_store.cluster_endpoint[0].port
  }
}

# Deployment Information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "deployment_account" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_tags" {
  description = "Common tags applied to resources"
  value = {
    Project     = "distributed-session-management"
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "memorydb-alb-session-management"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    memorydb_cluster = "~$150-300 (${var.memorydb_node_type} x ${var.memorydb_num_shards} shards)"
    application_load_balancer = "~$20-25"
    ecs_fargate_tasks = "~$15-30 (${var.ecs_desired_count} tasks)"
    data_transfer = "~$10-50 (varies by usage)"
    total_estimated = "~$195-405"
    note = "Costs vary by region and actual usage"
  }
}

# Health and Monitoring URLs
output "monitoring_dashboard_urls" {
  description = "URLs for monitoring dashboards"
  value = {
    ecs_cluster = "https://console.aws.amazon.com/ecs/home?region=${data.aws_region.current.name}#/clusters/${aws_ecs_cluster.main.name}"
    memorydb_cluster = "https://console.aws.amazon.com/memorydb/home?region=${data.aws_region.current.name}#/clusters/${aws_memorydb_cluster.session_store.name}"
    load_balancer = "https://console.aws.amazon.com/ec2/v2/home?region=${data.aws_region.current.name}#LoadBalancers:search=${aws_lb.main.name}"
    cloudwatch_logs = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${aws_cloudwatch_log_group.ecs_logs.name}"
  }
}