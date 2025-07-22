# Outputs for Advanced Blue-Green Deployments Infrastructure
# This file defines outputs that provide essential information about deployed resources

# ====================================
# Network and Load Balancer Outputs
# ====================================

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

output "alb_hosted_zone_id" {
  description = "Hosted zone ID for Route53 alias records"
  value       = aws_lb.main.zone_id
}

output "vpc_id" {
  description = "ID of the VPC used for deployment"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for deployment"
  value       = local.subnet_ids
}

# ====================================
# Security Group Outputs
# ====================================

output "alb_security_group_id" {
  description = "Security group ID for the Application Load Balancer"
  value       = aws_security_group.alb_sg.id
}

output "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_sg.id
}

# ====================================
# Target Group Outputs
# ====================================

output "blue_target_group_arn" {
  description = "ARN of the blue target group"
  value       = aws_lb_target_group.blue.arn
}

output "green_target_group_arn" {
  description = "ARN of the green target group"
  value       = aws_lb_target_group.green.arn
}

output "blue_target_group_name" {
  description = "Name of the blue target group"
  value       = aws_lb_target_group.blue.name
}

output "green_target_group_name" {
  description = "Name of the green target group"
  value       = aws_lb_target_group.green.name
}

# ====================================
# ECS Outputs
# ====================================

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
  value       = aws_ecs_service.app.name
}

output "ecs_service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.app.id
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.app.arn
}

output "ecs_task_definition_family" {
  description = "Family name of the ECS task definition"
  value       = aws_ecs_task_definition.app.family
}

# ====================================
# ECR Repository Outputs
# ====================================

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

# ====================================
# Lambda Function Outputs
# ====================================

output "lambda_function_name" {
  description = "Name of the main Lambda function"
  value       = aws_lambda_function.api_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the main Lambda function"
  value       = aws_lambda_function.api_function.arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the main Lambda function"
  value       = aws_lambda_function.api_function.qualified_arn
}

output "lambda_alias_arn" {
  description = "ARN of the Lambda production alias"
  value       = aws_lambda_alias.prod.arn
}

output "lambda_alias_name" {
  description = "Name of the Lambda production alias"
  value       = aws_lambda_alias.prod.name
}

# ====================================
# Deployment Hook Lambda Outputs
# ====================================

output "pre_deployment_hook_function_name" {
  description = "Name of the pre-deployment hook Lambda function"
  value       = aws_lambda_function.pre_deployment_hook.function_name
}

output "pre_deployment_hook_arn" {
  description = "ARN of the pre-deployment hook Lambda function"
  value       = aws_lambda_function.pre_deployment_hook.arn
}

output "post_deployment_hook_function_name" {
  description = "Name of the post-deployment hook Lambda function"
  value       = aws_lambda_function.post_deployment_hook.function_name
}

output "post_deployment_hook_arn" {
  description = "ARN of the post-deployment hook Lambda function"
  value       = aws_lambda_function.post_deployment_hook.arn
}

# ====================================
# IAM Role Outputs
# ====================================

output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

output "codedeploy_role_arn" {
  description = "ARN of the CodeDeploy service role"
  value       = aws_iam_role.codedeploy_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# ====================================
# CodeDeploy Outputs
# ====================================

output "codedeploy_ecs_app_name" {
  description = "Name of the CodeDeploy ECS application"
  value       = aws_codedeploy_app.ecs_app.name
}

output "codedeploy_ecs_app_id" {
  description = "ID of the CodeDeploy ECS application"
  value       = aws_codedeploy_app.ecs_app.id
}

output "codedeploy_lambda_app_name" {
  description = "Name of the CodeDeploy Lambda application"
  value       = aws_codedeploy_app.lambda_app.name
}

output "codedeploy_lambda_app_id" {
  description = "ID of the CodeDeploy Lambda application"
  value       = aws_codedeploy_app.lambda_app.id
}

output "codedeploy_ecs_deployment_group_name" {
  description = "Name of the ECS deployment group"
  value       = aws_codedeploy_deployment_group.ecs_deployment_group.deployment_group_name
}

output "codedeploy_lambda_deployment_group_name" {
  description = "Name of the Lambda deployment group"
  value       = aws_codedeploy_deployment_group.lambda_deployment_group.deployment_group_name
}

# ====================================
# CloudWatch Outputs
# ====================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for ECS"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for ECS"
  value       = aws_cloudwatch_log_group.ecs_logs.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.deployment_dashboard.dashboard_name}"
}

# ====================================
# SNS and Notification Outputs
# ====================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for deployment notifications (if created)"
  value       = var.notification_email != "" ? aws_sns_topic.deployment_notifications[0].arn : null
}

# ====================================
# Alarm Outputs
# ====================================

output "alb_error_rate_alarm_name" {
  description = "Name of the ALB error rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.alb_error_rate.alarm_name
}

output "alb_response_time_alarm_name" {
  description = "Name of the ALB response time CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.alb_response_time.alarm_name
}

output "lambda_error_rate_alarm_name" {
  description = "Name of the Lambda error rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_error_rate.alarm_name
}

output "lambda_duration_alarm_name" {
  description = "Name of the Lambda duration CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name
}

# ====================================
# Application Access Information
# ====================================

output "application_url" {
  description = "URL to access the deployed application"
  value       = "http://${aws_lb.main.dns_name}"
}

output "health_check_url" {
  description = "URL for application health checks"
  value       = "http://${aws_lb.main.dns_name}${var.health_check_path}"
}

# ====================================
# Deployment Information
# ====================================

output "deployment_commands" {
  description = "Commands to trigger blue-green deployments"
  value = {
    ecs_deployment = "aws deploy create-deployment --application-name ${aws_codedeploy_app.ecs_app.name} --deployment-group-name ${aws_codedeploy_deployment_group.ecs_deployment_group.deployment_group_name} --deployment-config-name ${var.ecs_deployment_config}"
    lambda_deployment = "aws deploy create-deployment --application-name ${aws_codedeploy_app.lambda_app.name} --deployment-group-name ${aws_codedeploy_deployment_group.lambda_deployment_group.deployment_group_name} --deployment-config-name ${var.lambda_deployment_config}"
  }
}

# ====================================
# Configuration Summary
# ====================================

output "deployment_configuration" {
  description = "Summary of deployment configuration"
  value = {
    project_name                    = var.project_name
    environment                     = var.environment
    aws_region                     = var.aws_region
    ecs_deployment_config          = var.ecs_deployment_config
    lambda_deployment_config       = var.lambda_deployment_config
    auto_rollback_enabled          = var.auto_rollback_enabled
    termination_wait_time_minutes  = var.termination_wait_time_in_minutes
  }
}

# ====================================
# Resource Summary
# ====================================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    alb_dns_name               = aws_lb.main.dns_name
    ecs_cluster_name          = aws_ecs_cluster.main.name
    ecs_service_name          = aws_ecs_service.app.name
    lambda_function_name      = aws_lambda_function.api_function.function_name
    ecr_repository_url        = aws_ecr_repository.app_repository.repository_url
    codedeploy_ecs_app_name   = aws_codedeploy_app.ecs_app.name
    codedeploy_lambda_app_name = aws_codedeploy_app.lambda_app.name
    cloudwatch_dashboard_name = aws_cloudwatch_dashboard.deployment_dashboard.dashboard_name
  }
}