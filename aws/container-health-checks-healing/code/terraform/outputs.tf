# VPC and Networking Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.main.id
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

# Load Balancer Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.main.arn
}

output "application_url" {
  description = "URL to access the application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "health_check_url" {
  description = "URL for health check endpoint"
  value       = "http://${aws_lb.main.dns_name}${var.health_check_path}"
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "ecs_service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.main.id
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.main.arn
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution.arn
}

# Auto Scaling Outputs
output "autoscaling_target_resource_id" {
  description = "Resource ID of the auto scaling target"
  value       = aws_appautoscaling_target.ecs_target.resource_id
}

output "cpu_scaling_policy_arn" {
  description = "ARN of the CPU scaling policy"
  value       = aws_appautoscaling_policy.ecs_cpu_policy.arn
}

output "memory_scaling_policy_arn" {
  description = "ARN of the memory scaling policy"
  value       = aws_appautoscaling_policy.ecs_memory_policy.arn
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.arn
}

output "unhealthy_targets_alarm_name" {
  description = "Name of the unhealthy targets alarm"
  value       = aws_cloudwatch_metric_alarm.unhealthy_targets.alarm_name
}

output "high_response_time_alarm_name" {
  description = "Name of the high response time alarm"
  value       = aws_cloudwatch_metric_alarm.high_response_time.alarm_name
}

output "low_running_tasks_alarm_name" {
  description = "Name of the low running tasks alarm"
  value       = aws_cloudwatch_metric_alarm.low_running_tasks.alarm_name
}

# SNS and Lambda Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "lambda_function_name" {
  description = "Name of the self-healing Lambda function"
  value       = aws_lambda_function.self_healing.function_name
}

output "lambda_function_arn" {
  description = "ARN of the self-healing Lambda function"
  value       = aws_lambda_function.self_healing.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# EKS Outputs (conditional)
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].name : null
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].arn : null
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].endpoint : null
}

output "eks_cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = var.enable_eks ? aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id : null
}

output "eks_node_group_arn" {
  description = "ARN of the EKS node group"
  value       = var.enable_eks ? aws_eks_node_group.main[0].arn : null
}

output "eks_node_group_status" {
  description = "Status of the EKS node group"
  value       = var.enable_eks ? aws_eks_node_group.main[0].status : null
}

# Resource Identifiers
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

# Monitoring and Debugging Information
output "container_insights_enabled" {
  description = "Whether Container Insights is enabled for the ECS cluster"
  value       = true
}

output "health_check_configuration" {
  description = "Health check configuration summary"
  value = {
    path                = var.health_check_path
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    grace_period        = var.health_check_grace_period
  }
}

output "auto_scaling_configuration" {
  description = "Auto scaling configuration summary"
  value = {
    min_capacity         = var.ecs_min_capacity
    max_capacity         = var.ecs_max_capacity
    cpu_target_value     = var.cpu_target_value
    memory_target_value  = var.memory_target_value
    scale_out_cooldown   = var.scale_out_cooldown
    scale_in_cooldown    = var.scale_in_cooldown
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for verifying the deployment"
  value = {
    verify_alb_health = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.main.arn}"
    check_ecs_service = "aws ecs describe-services --cluster ${aws_ecs_cluster.main.name} --services ${aws_ecs_service.main.name}"
    view_logs         = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.ecs.name}"
    test_application  = "curl -s http://${aws_lb.main.dns_name}${var.health_check_path}"
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = {
    fargate_pricing     = "ECS Fargate pricing is based on vCPU and memory resources allocated"
    alb_pricing         = "ALB pricing includes hourly charge plus per-LCU usage"
    cloudwatch_pricing  = "CloudWatch pricing includes log ingestion and storage costs"
    auto_scaling_benefit = "Auto scaling helps optimize costs by adjusting capacity based on demand"
  }
}

# Security Information
output "security_considerations" {
  description = "Security considerations for the deployment"
  value = {
    security_groups = "Security groups follow least privilege principle"
    iam_roles      = "IAM roles have minimal required permissions"
    vpc_isolation  = "Resources are isolated within a dedicated VPC"
    encryption     = "Consider enabling encryption for logs and ALB traffic"
  }
}