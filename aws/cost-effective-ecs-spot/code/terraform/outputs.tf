# ==============================================================================
# CLUSTER OUTPUTS
# ==============================================================================

output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "cluster_capacity_providers" {
  description = "List of capacity providers associated with the cluster"
  value       = aws_ecs_cluster.main.capacity_providers
}

# ==============================================================================
# CAPACITY PROVIDER OUTPUTS
# ==============================================================================

output "capacity_provider_name" {
  description = "Name of the ECS capacity provider"
  value       = aws_ecs_capacity_provider.main.name
}

output "capacity_provider_arn" {
  description = "ARN of the ECS capacity provider"
  value       = aws_ecs_capacity_provider.main.arn
}

output "capacity_provider_tags" {
  description = "Tags applied to the capacity provider"
  value       = aws_ecs_capacity_provider.main.tags_all
}

# ==============================================================================
# AUTO SCALING GROUP OUTPUTS
# ==============================================================================

output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.name
}

output "auto_scaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.arn
}

output "auto_scaling_group_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.min_size
}

output "auto_scaling_group_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.max_size
}

output "auto_scaling_group_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.desired_capacity
}

output "auto_scaling_group_availability_zones" {
  description = "Availability zones used by the Auto Scaling Group"
  value       = aws_autoscaling_group.main.availability_zones
}

# ==============================================================================
# LAUNCH TEMPLATE OUTPUTS
# ==============================================================================

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.main.id
}

output "launch_template_name" {
  description = "Name of the launch template"
  value       = aws_launch_template.main.name
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.main.latest_version
}

output "launch_template_instance_types" {
  description = "Instance types configured in the launch template"
  value       = var.instance_types
}

# ==============================================================================
# SERVICE OUTPUTS
# ==============================================================================

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.main.name
}

output "service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.main.id
}

output "service_desired_count" {
  description = "Desired count of the ECS service"
  value       = aws_ecs_service.main.desired_count
}

output "service_task_definition" {
  description = "Task definition used by the ECS service"
  value       = aws_ecs_service.main.task_definition
}

# ==============================================================================
# TASK DEFINITION OUTPUTS
# ==============================================================================

output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.main.arn
}

output "task_definition_family" {
  description = "Family name of the ECS task definition"
  value       = aws_ecs_task_definition.main.family
}

output "task_definition_revision" {
  description = "Revision of the ECS task definition"
  value       = aws_ecs_task_definition.main.revision
}

output "task_definition_cpu" {
  description = "CPU units allocated to the task definition"
  value       = aws_ecs_task_definition.main.cpu
}

output "task_definition_memory" {
  description = "Memory allocated to the task definition"
  value       = aws_ecs_task_definition.main.memory
}

# ==============================================================================
# NETWORKING OUTPUTS
# ==============================================================================

output "vpc_id" {
  description = "ID of the VPC used for the deployment"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for the deployment"
  value       = local.subnet_ids
}

output "security_group_id" {
  description = "ID of the security group for ECS instances"
  value       = aws_security_group.ecs_instances.id
}

output "security_group_name" {
  description = "Name of the security group for ECS instances"
  value       = aws_security_group.ecs_instances.name
}

# ==============================================================================
# IAM OUTPUTS
# ==============================================================================

output "ecs_instance_role_arn" {
  description = "ARN of the ECS instance IAM role"
  value       = aws_iam_role.ecs_instance_role.arn
}

output "ecs_instance_role_name" {
  description = "Name of the ECS instance IAM role"
  value       = aws_iam_role.ecs_instance_role.name
}

output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_execution_role_name" {
  description = "Name of the ECS task execution IAM role"
  value       = aws_iam_role.ecs_task_execution_role.name
}

output "ecs_instance_profile_name" {
  description = "Name of the ECS instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.name
}

output "ecs_instance_profile_arn" {
  description = "ARN of the ECS instance profile"
  value       = aws_iam_instance_profile.ecs_instance_profile.arn
}

# ==============================================================================
# AUTO SCALING OUTPUTS
# ==============================================================================

output "auto_scaling_target_arn" {
  description = "ARN of the application auto scaling target"
  value       = var.enable_service_auto_scaling ? aws_appautoscaling_target.ecs_service[0].arn : null
}

output "auto_scaling_policy_arn" {
  description = "ARN of the application auto scaling policy"
  value       = var.enable_service_auto_scaling ? aws_appautoscaling_policy.ecs_service_cpu[0].arn : null
}

output "auto_scaling_policy_name" {
  description = "Name of the application auto scaling policy"
  value       = var.enable_service_auto_scaling ? aws_appautoscaling_policy.ecs_service_cpu[0].name : null
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs_logs.arn
}

output "cloudwatch_log_retention_days" {
  description = "Log retention period in days"
  value       = aws_cloudwatch_log_group.ecs_logs.retention_in_days
}

# ==============================================================================
# COST OPTIMIZATION OUTPUTS
# ==============================================================================

output "cost_optimization_summary" {
  description = "Summary of cost optimization configurations"
  value = {
    on_demand_base_capacity           = var.on_demand_base_capacity
    on_demand_percentage_above_base   = var.on_demand_percentage_above_base
    spot_instance_pools              = var.spot_instance_pools
    spot_max_price                   = var.spot_max_price
    instance_types                   = var.instance_types
    diversified_allocation           = true
    managed_instance_draining        = true
    expected_cost_savings            = "50-70% compared to pure On-Demand"
  }
}

# ==============================================================================
# DEPLOYMENT VERIFICATION OUTPUTS
# ==============================================================================

output "deployment_verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_cluster_status = "aws ecs describe-clusters --clusters ${aws_ecs_cluster.main.name} --query 'clusters[0].status'"
    check_service_status = "aws ecs describe-services --cluster ${aws_ecs_cluster.main.name} --services ${aws_ecs_service.main.name} --query 'services[0].status'"
    check_running_tasks  = "aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${aws_ecs_service.main.name}"
    check_instances      = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.main.name} --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState]'"
    check_spot_pricing   = "aws ec2 describe-spot-price-history --instance-types ${join(" ", var.instance_types)} --product-descriptions 'Linux/UNIX' --max-items 10"
  }
}

# ==============================================================================
# RESOURCE TAGS
# ==============================================================================

output "resource_tags" {
  description = "Common tags applied to all resources"
  value = merge(
    {
      Project     = "cost-effective-ecs-spot"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}