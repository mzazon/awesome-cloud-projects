# Load Balancer Outputs
output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.web_app.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.web_app.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.web_app.zone_id
}

output "load_balancer_hosted_zone_id" {
  description = "Hosted zone ID of the Application Load Balancer"
  value       = aws_lb.web_app.zone_id
}

output "application_url" {
  description = "URL to access the web application"
  value       = "http://${aws_lb.web_app.dns_name}"
}

# Target Group Outputs
output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.web_app.arn
}

output "target_group_name" {
  description = "Name of the Target Group"
  value       = aws_lb_target_group.web_app.name
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the Target Group"
  value       = aws_lb_target_group.web_app.arn_suffix
}

# Auto Scaling Group Outputs
output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.web_app.arn
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web_app.name
}

output "autoscaling_group_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.web_app.min_size
}

output "autoscaling_group_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.web_app.max_size
}

output "autoscaling_group_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  value       = aws_autoscaling_group.web_app.desired_capacity
}

output "autoscaling_group_availability_zones" {
  description = "Availability zones used by the Auto Scaling Group"
  value       = aws_autoscaling_group.web_app.availability_zones
}

# Launch Template Outputs
output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.web_app.id
}

output "launch_template_name" {
  description = "Name of the Launch Template"
  value       = aws_launch_template.web_app.name
}

output "launch_template_latest_version" {
  description = "Latest version of the Launch Template"
  value       = aws_launch_template.web_app.latest_version
}

# Security Group Outputs
output "security_group_id" {
  description = "ID of the Security Group"
  value       = aws_security_group.web_app.id
}

output "security_group_name" {
  description = "Name of the Security Group"
  value       = aws_security_group.web_app.name
}

# Scaling Policy Outputs
output "cpu_scaling_policy_arn" {
  description = "ARN of the CPU target tracking scaling policy"
  value       = aws_autoscaling_policy.cpu_target_tracking.arn
}

output "cpu_scaling_policy_name" {
  description = "Name of the CPU target tracking scaling policy"
  value       = aws_autoscaling_policy.cpu_target_tracking.name
}

output "alb_request_scaling_policy_arn" {
  description = "ARN of the ALB request count target tracking scaling policy"
  value       = aws_autoscaling_policy.alb_request_count_tracking.arn
}

output "alb_request_scaling_policy_name" {
  description = "Name of the ALB request count target tracking scaling policy"
  value       = aws_autoscaling_policy.alb_request_count_tracking.name
}

# CloudWatch Alarm Outputs
output "high_cpu_alarm_arn" {
  description = "ARN of the high CPU CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.high_cpu[0].arn : null
}

output "unhealthy_targets_alarm_arn" {
  description = "ARN of the unhealthy targets CloudWatch alarm"
  value       = var.create_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.unhealthy_targets[0].arn : null
}

# Scheduled Scaling Outputs
output "scale_up_schedule_arn" {
  description = "ARN of the scale up scheduled action"
  value       = var.enable_scheduled_scaling ? aws_autoscaling_schedule.scale_up_business_hours[0].arn : null
}

output "scale_down_schedule_arn" {
  description = "ARN of the scale down scheduled action"
  value       = var.enable_scheduled_scaling ? aws_autoscaling_schedule.scale_down_after_hours[0].arn : null
}

# VPC and Network Outputs
output "vpc_id" {
  description = "ID of the VPC where resources are deployed"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used by the Auto Scaling Group"
  value       = local.subnet_ids
}

# Instance Information Outputs
output "instance_type" {
  description = "Instance type used by the Auto Scaling Group"
  value       = var.instance_type
}

output "ami_id" {
  description = "AMI ID used by the Launch Template"
  value       = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  description = "Name of the AMI used by the Launch Template"
  value       = data.aws_ami.amazon_linux.name
}

# Resource Name Outputs
output "resource_prefix" {
  description = "Prefix used for naming resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Monitoring and Scaling Configuration Outputs
output "scaling_configuration" {
  description = "Auto Scaling configuration summary"
  value = {
    min_size                     = aws_autoscaling_group.web_app.min_size
    max_size                     = aws_autoscaling_group.web_app.max_size
    desired_capacity             = aws_autoscaling_group.web_app.desired_capacity
    health_check_grace_period    = aws_autoscaling_group.web_app.health_check_grace_period
    health_check_type            = aws_autoscaling_group.web_app.health_check_type
    default_cooldown             = aws_autoscaling_group.web_app.default_cooldown
    cpu_target_value             = var.cpu_target_value
    alb_request_count_target     = var.alb_request_count_target
    enable_scheduled_scaling     = var.enable_scheduled_scaling
    enable_detailed_monitoring   = var.enable_detailed_monitoring
  }
}

output "load_balancer_configuration" {
  description = "Load Balancer configuration summary"
  value = {
    type                      = aws_lb.web_app.load_balancer_type
    scheme                    = aws_lb.web_app.internal ? "internal" : "internet-facing"
    enable_deletion_protection = aws_lb.web_app.enable_deletion_protection
    enable_http2              = aws_lb.web_app.enable_http2
    security_groups           = aws_lb.web_app.security_groups
    subnets                   = aws_lb.web_app.subnets
  }
}

output "target_group_configuration" {
  description = "Target Group configuration summary"
  value = {
    port                    = aws_lb_target_group.web_app.port
    protocol                = aws_lb_target_group.web_app.protocol
    vpc_id                  = aws_lb_target_group.web_app.vpc_id
    health_check_enabled    = aws_lb_target_group.web_app.health_check[0].enabled
    health_check_path       = aws_lb_target_group.web_app.health_check[0].path
    health_check_interval   = aws_lb_target_group.web_app.health_check[0].interval
    health_check_timeout    = aws_lb_target_group.web_app.health_check[0].timeout
    healthy_threshold       = aws_lb_target_group.web_app.health_check[0].healthy_threshold
    unhealthy_threshold     = aws_lb_target_group.web_app.health_check[0].unhealthy_threshold
    deregistration_delay    = aws_lb_target_group.web_app.deregistration_delay
  }
}