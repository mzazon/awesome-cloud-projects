# Output values for cross-account service discovery with VPC Lattice and ECS

# Account and Region Information
output "account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

# VPC Lattice Service Network Outputs
output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.arn
}

output "service_network_name" {
  description = "Name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.name
}

# VPC Lattice Service Outputs
output "lattice_service_id" {
  description = "ID of the VPC Lattice service"
  value       = aws_vpclattice_service.producer.id
}

output "lattice_service_arn" {
  description = "ARN of the VPC Lattice service"
  value       = aws_vpclattice_service.producer.arn
}

output "lattice_service_name" {
  description = "Name of the VPC Lattice service"
  value       = aws_vpclattice_service.producer.name
}

output "lattice_service_dns_name" {
  description = "DNS name of the VPC Lattice service"
  value       = aws_vpclattice_service.producer.dns_entry
}

# VPC Lattice Target Group Outputs
output "target_group_id" {
  description = "ID of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.producer.id
}

output "target_group_arn" {
  description = "ARN of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.producer.arn
}

output "target_group_name" {
  description = "Name of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.producer.name
}

# VPC Lattice Listener Outputs
output "listener_id" {
  description = "ID of the VPC Lattice listener"
  value       = aws_vpclattice_listener.producer.id
}

output "listener_arn" {
  description = "ARN of the VPC Lattice listener"
  value       = aws_vpclattice_listener.producer.arn
}

# ECS Cluster Outputs
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

# ECS Service Outputs
output "ecs_service_id" {
  description = "ID of the ECS service"
  value       = aws_ecs_service.producer.id
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.producer.name
}

output "ecs_service_cluster" {
  description = "Cluster of the ECS service"
  value       = aws_ecs_service.producer.cluster
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.producer.arn
}

output "ecs_task_definition_family" {
  description = "Family of the ECS task definition"
  value       = aws_ecs_task_definition.producer.family
}

output "ecs_task_definition_revision" {
  description = "Revision of the ECS task definition"
  value       = aws_ecs_task_definition.producer.revision
}

# IAM Role Outputs
output "ecs_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_execution_role_name" {
  description = "Name of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.name
}

output "eventbridge_logs_role_arn" {
  description = "ARN of the EventBridge logs role"
  value       = var.enable_monitoring ? aws_iam_role.eventbridge_logs_role[0].arn : null
}

# AWS RAM Resource Share Outputs
output "resource_share_id" {
  description = "ID of the AWS RAM resource share"
  value       = var.enable_resource_sharing ? aws_ram_resource_share.lattice_share[0].id : null
}

output "resource_share_arn" {
  description = "ARN of the AWS RAM resource share"
  value       = var.enable_resource_sharing ? aws_ram_resource_share.lattice_share[0].arn : null
}

output "resource_share_name" {
  description = "Name of the AWS RAM resource share"
  value       = var.enable_resource_sharing ? aws_ram_resource_share.lattice_share[0].name : null
}

output "resource_share_status" {
  description = "Status of the AWS RAM resource share"
  value       = var.enable_resource_sharing ? aws_ram_resource_share.lattice_share[0].status : null
}

# Security Group Outputs
output "ecs_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = var.create_security_groups ? aws_security_group.ecs_tasks[0].id : null
}

output "ecs_security_group_arn" {
  description = "ARN of the ECS tasks security group"
  value       = var.create_security_groups ? aws_security_group.ecs_tasks[0].arn : null
}

# VPC and Networking Outputs
output "vpc_id" {
  description = "ID of the VPC used for deployment"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for ECS service deployment"
  value       = local.subnet_ids
}

# CloudWatch Log Group Outputs
output "ecs_log_group_name" {
  description = "Name of the ECS CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

output "ecs_log_group_arn" {
  description = "ARN of the ECS CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs_logs.arn
}

output "vpc_lattice_events_log_group_name" {
  description = "Name of the VPC Lattice events CloudWatch log group"
  value       = var.enable_monitoring ? aws_cloudwatch_log_group.vpc_lattice_events[0].name : null
}

output "vpc_lattice_events_log_group_arn" {
  description = "ARN of the VPC Lattice events CloudWatch log group"
  value       = var.enable_monitoring ? aws_cloudwatch_log_group.vpc_lattice_events[0].arn : null
}

# EventBridge Rule Outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for VPC Lattice events"
  value       = var.enable_monitoring ? aws_cloudwatch_event_rule.vpc_lattice_events[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for VPC Lattice events"
  value       = var.enable_monitoring ? aws_cloudwatch_event_rule.vpc_lattice_events[0].arn : null
}

# CloudWatch Dashboard Outputs
output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value = var.enable_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main[0].dashboard_name}" : null
}

# Service Discovery Information
output "service_discovery_dns" {
  description = "DNS name for service discovery within VPC Lattice"
  value       = aws_vpclattice_service.producer.dns_entry
}

output "service_endpoint" {
  description = "Service endpoint for cross-account communication"
  value       = "https://${aws_vpclattice_service.producer.dns_entry[0].domain_name}"
}

# Cross-Account Configuration Information
output "account_b_id" {
  description = "Account B ID for cross-account sharing"
  value       = var.account_b_id
}

output "sharing_enabled" {
  description = "Whether resource sharing is enabled"
  value       = var.enable_resource_sharing
}

# Resource Naming Information
output "resource_prefix" {
  description = "Resource prefix used for naming"
  value       = var.project_name
}

output "random_suffix" {
  description = "Random suffix added to resource names"
  value       = local.suffix
}

# Monitoring Configuration
output "monitoring_enabled" {
  description = "Whether monitoring and EventBridge rules are enabled"
  value       = var.enable_monitoring
}

output "dashboard_enabled" {
  description = "Whether CloudWatch dashboard is enabled"
  value       = var.enable_dashboard
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of the deployed configuration"
  value = {
    service_network = {
      name = aws_vpclattice_service_network.main.name
      id   = aws_vpclattice_service_network.main.id
      arn  = aws_vpclattice_service_network.main.arn
    }
    lattice_service = {
      name     = aws_vpclattice_service.producer.name
      id       = aws_vpclattice_service.producer.id
      arn      = aws_vpclattice_service.producer.arn
      dns_name = aws_vpclattice_service.producer.dns_entry
    }
    ecs_cluster = {
      name = aws_ecs_cluster.main.name
      id   = aws_ecs_cluster.main.id
      arn  = aws_ecs_cluster.main.arn
    }
    ecs_service = {
      name           = aws_ecs_service.producer.name
      desired_count  = aws_ecs_service.producer.desired_count
      task_definition = aws_ecs_task_definition.producer.arn
    }
    resource_sharing = {
      enabled    = var.enable_resource_sharing
      share_name = var.enable_resource_sharing ? aws_ram_resource_share.lattice_share[0].name : null
      account_b  = var.account_b_id
    }
    monitoring = {
      enabled           = var.enable_monitoring
      dashboard_enabled = var.enable_dashboard
      log_retention     = var.log_retention_days
    }
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_service_network = "aws vpc-lattice get-service-network --service-network-identifier ${aws_vpclattice_service_network.main.id}"
    check_ecs_service     = "aws ecs describe-services --cluster ${aws_ecs_cluster.main.name} --services ${aws_ecs_service.producer.name}"
    check_target_health   = "aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.producer.id}"
    check_resource_share  = var.enable_resource_sharing ? "aws ram get-resource-shares --resource-owner SELF --name ${aws_ram_resource_share.lattice_share[0].name}" : "Resource sharing not enabled"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps for cross-account configuration"
  value = var.enable_resource_sharing ? [
    "1. In Account B, accept the resource share invitation: aws ram get-resource-share-invitations",
    "2. Associate Account B VPC with the shared service network",
    "3. Create consumer services in Account B that can discover this producer service",
    "4. Test cross-account communication using the service DNS name: ${aws_vpclattice_service.producer.dns_entry[0].domain_name}",
    "5. Monitor events in CloudWatch Logs: ${var.enable_monitoring ? aws_cloudwatch_log_group.vpc_lattice_events[0].name : "Events logging not enabled"}"
  ] : [
    "Resource sharing is disabled. Enable it by setting enable_resource_sharing = true to allow cross-account access."
  ]
}