# Auto Scaling Group outputs
output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.name
}

output "auto_scaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.arn
}

output "auto_scaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.id
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

# Launch Template outputs
output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.main.id
}

output "launch_template_arn" {
  description = "ARN of the Launch Template"
  value       = aws_launch_template.main.arn
}

output "launch_template_latest_version" {
  description = "Latest version of the Launch Template"
  value       = aws_launch_template.main.latest_version
}

# Load Balancer outputs (conditional)
output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].arn : null
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].dns_name : null
}

output "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the load balancer"
  value       = var.enable_load_balancer ? aws_lb.main[0].zone_id : null
}

output "load_balancer_hosted_zone_id" {
  description = "Canonical hosted zone ID of the load balancer (for DNS)"
  value       = var.enable_load_balancer ? aws_lb.main[0].zone_id : null
}

output "application_url" {
  description = "URL of the application (if load balancer is enabled)"
  value       = var.enable_load_balancer ? "http://${aws_lb.main[0].dns_name}" : "Load balancer disabled - access instances directly"
}

# Target Group outputs (conditional)
output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = var.enable_load_balancer ? aws_lb_target_group.main[0].arn : null
}

output "target_group_name" {
  description = "Name of the Target Group"
  value       = var.enable_load_balancer ? aws_lb_target_group.main[0].name : null
}

# Security Group outputs
output "asg_security_group_id" {
  description = "ID of the Auto Scaling Group security group"
  value       = aws_security_group.asg_instances.id
}

output "asg_security_group_arn" {
  description = "ARN of the Auto Scaling Group security group"
  value       = aws_security_group.asg_instances.arn
}

output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group"
  value       = var.enable_load_balancer ? aws_security_group.alb[0].id : null
}

output "alb_security_group_arn" {
  description = "ARN of the Application Load Balancer security group"
  value       = var.enable_load_balancer ? aws_security_group.alb[0].arn : null
}

# IAM outputs
output "ec2_instance_role_arn" {
  description = "ARN of the EC2 instance IAM role"
  value       = aws_iam_role.ec2_instance_role.arn
}

output "ec2_instance_role_name" {
  description = "Name of the EC2 instance IAM role"
  value       = aws_iam_role.ec2_instance_role.name
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_instance_profile.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_instance_profile.name
}

# Scaling Policy outputs
output "cpu_scaling_policy_arn" {
  description = "ARN of the CPU-based scaling policy"
  value       = aws_autoscaling_policy.cpu_scale.arn
}

output "cpu_scaling_policy_name" {
  description = "Name of the CPU-based scaling policy"
  value       = aws_autoscaling_policy.cpu_scale.name
}

output "network_scaling_policy_arn" {
  description = "ARN of the network-based scaling policy"
  value       = aws_autoscaling_policy.network_scale.arn
}

output "network_scaling_policy_name" {
  description = "Name of the network-based scaling policy"
  value       = aws_autoscaling_policy.network_scale.name
}

# SNS outputs (conditional)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for Auto Scaling notifications"
  value       = var.enable_notifications ? aws_sns_topic.asg_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for Auto Scaling notifications"
  value       = var.enable_notifications ? aws_sns_topic.asg_notifications[0].name : null
}

# VPC and Networking outputs
output "vpc_id" {
  description = "ID of the VPC used"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used by the Auto Scaling Group"
  value       = local.subnet_ids
}

output "availability_zones" {
  description = "List of availability zones used by the Auto Scaling Group"
  value       = var.create_vpc ? local.azs : []
}

# Mixed Instance Policy Configuration outputs
output "mixed_instance_policy_summary" {
  description = "Summary of the mixed instance policy configuration"
  value = {
    on_demand_base_capacity                  = var.on_demand_base_capacity
    on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base_capacity
    spot_allocation_strategy                 = var.spot_allocation_strategy
    spot_instance_pools                      = var.spot_instance_pools
    spot_max_price                           = var.spot_max_price != "" ? var.spot_max_price : "On-Demand price"
    capacity_rebalance_enabled               = var.enable_capacity_rebalance
  }
}

output "instance_types_configuration" {
  description = "List of instance types and their weighted capacity"
  value = [
    for instance in var.instance_types : {
      instance_type     = instance.instance_type
      weighted_capacity = instance.weighted_capacity
    }
  ]
}

# Cost optimization outputs
output "cost_optimization_summary" {
  description = "Summary of cost optimization features enabled"
  value = {
    spot_instances_enabled     = var.on_demand_percentage_above_base_capacity < 100
    capacity_rebalance_enabled = var.enable_capacity_rebalance
    mixed_instance_types       = length(var.instance_types)
    estimated_spot_percentage  = max(0, 100 - var.on_demand_percentage_above_base_capacity - (var.on_demand_base_capacity * 100 / var.desired_capacity))
  }
}

# Monitoring and observability outputs
output "cloudwatch_namespace" {
  description = "CloudWatch namespace for custom metrics"
  value       = "AutoScaling/MixedInstances"
}

output "monitoring_enabled" {
  description = "Whether detailed monitoring is enabled for instances"
  value       = var.instance_monitoring
}

# Scaling configuration outputs
output "scaling_configuration" {
  description = "Auto Scaling configuration summary"
  value = {
    min_size                     = var.min_size
    max_size                     = var.max_size
    desired_capacity             = var.desired_capacity
    health_check_type            = var.health_check_type
    health_check_grace_period    = var.health_check_grace_period
    cpu_target_value             = var.cpu_target_value
    network_target_value         = var.network_target_value
    scale_cooldown               = var.scale_cooldown
  }
}

# Resource naming outputs
output "resource_name_prefix" {
  description = "Prefix used for naming all resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used in resource names"
  value       = random_string.suffix.result
}

# Environment and project information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Commands for testing and validation
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_asg_status = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.main.name} --region ${var.aws_region}"
    check_instances  = "aws autoscaling describe-auto-scaling-instances --region ${var.aws_region} --query \"AutoScalingInstances[?AutoScalingGroupName=='${aws_autoscaling_group.main.name}'].[InstanceId,InstanceType,AvailabilityZone,LifecycleState]\""
    test_application = var.enable_load_balancer ? "curl -s http://${aws_lb.main[0].dns_name}" : "Check individual instance IPs for web server response"
    check_scaling    = "aws autoscaling describe-scaling-activities --auto-scaling-group-name ${aws_autoscaling_group.main.name} --region ${var.aws_region}"
  }
}

# Cleanup commands
output "cleanup_commands" {
  description = "Commands to clean up resources manually if needed"
  value = {
    scale_down_asg = "aws autoscaling update-auto-scaling-group --auto-scaling-group-name ${aws_autoscaling_group.main.name} --min-size 0 --max-size 0 --desired-capacity 0 --region ${var.aws_region}"
    delete_asg     = "aws autoscaling delete-auto-scaling-group --auto-scaling-group-name ${aws_autoscaling_group.main.name} --force-delete --region ${var.aws_region}"
  }
}