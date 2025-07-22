# Output values for the EC2 Fleet Management deployment

output "vpc_id" {
  description = "ID of the VPC used for the fleet"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for fleet instances"
  value       = local.subnet_ids
}

output "availability_zones" {
  description = "List of availability zones used for fleet instances"
  value       = local.availability_zones
}

output "security_group_id" {
  description = "ID of the security group for fleet instances"
  value       = aws_security_group.fleet_sg.id
}

output "security_group_name" {
  description = "Name of the security group for fleet instances"
  value       = aws_security_group.fleet_sg.name
}

output "launch_template_id" {
  description = "ID of the launch template used for fleet instances"
  value       = aws_launch_template.fleet_template.id
}

output "launch_template_name" {
  description = "Name of the launch template used for fleet instances"
  value       = aws_launch_template.fleet_template.name
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.fleet_template.latest_version
}

output "ec2_fleet_id" {
  description = "ID of the EC2 Fleet"
  value       = aws_ec2_fleet.main_fleet.id
}

output "ec2_fleet_state" {
  description = "Current state of the EC2 Fleet"
  value       = aws_ec2_fleet.main_fleet.fleet_state
}

output "spot_fleet_id" {
  description = "ID of the Spot Fleet request"
  value       = aws_spot_fleet_request.main_spot_fleet.id
}

output "spot_fleet_state" {
  description = "Current state of the Spot Fleet request"
  value       = aws_spot_fleet_request.main_spot_fleet.spot_fleet_request_state
}

output "spot_fleet_role_arn" {
  description = "ARN of the IAM role for Spot Fleet"
  value       = aws_iam_role.spot_fleet_role.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_profile.arn
}

output "key_pair_name" {
  description = "Name of the key pair used for instances"
  value       = var.create_key_pair ? aws_key_pair.fleet_key[0].key_name : var.key_pair_name
}

output "ami_id" {
  description = "ID of the AMI used for instances"
  value       = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  description = "Name of the AMI used for instances"
  value       = data.aws_ami.amazon_linux.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.fleet_dashboard[0].dashboard_name}" : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for fleet instances"
  value       = aws_cloudwatch_log_group.fleet_logs.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for fleet notifications"
  value       = aws_sns_topic.fleet_notifications.arn
}

output "cpu_alarm_name" {
  description = "Name of the high CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
}

output "spot_capacity_alarm_name" {
  description = "Name of the Spot Fleet capacity alarm"
  value       = aws_cloudwatch_metric_alarm.spot_fleet_capacity.alarm_name
}

# Fleet configuration outputs
output "fleet_configuration" {
  description = "Configuration summary of the deployed fleets"
  value = {
    ec2_fleet = {
      id                    = aws_ec2_fleet.main_fleet.id
      total_capacity        = var.ec2_fleet_target_capacity
      on_demand_capacity    = var.ec2_fleet_on_demand_capacity
      spot_capacity         = var.ec2_fleet_spot_capacity
      instance_types        = var.instance_types
      allocation_strategy   = "capacity-optimized"
    }
    spot_fleet = {
      id                    = aws_spot_fleet_request.main_spot_fleet.id
      target_capacity       = var.spot_fleet_target_capacity
      max_spot_price        = var.spot_max_price
      allocation_strategy   = var.fleet_allocation_strategy
      instance_types        = var.instance_types
    }
  }
}

# Cost optimization insights
output "cost_optimization_summary" {
  description = "Summary of cost optimization features enabled"
  value = {
    spot_instances_enabled     = var.ec2_fleet_spot_capacity > 0
    mixed_instance_types       = length(var.instance_types) > 1
    capacity_optimized_allocation = true
    diversified_on_demand      = true
    unhealthy_instance_replacement = var.replace_unhealthy_instances
    spot_max_price             = var.spot_max_price
    estimated_cost_savings     = "Up to 90% compared to On-Demand only"
  }
}

# Instance access information
output "instance_access_info" {
  description = "Information for accessing fleet instances"
  value = {
    ssh_command_template = "ssh -i ${var.create_key_pair ? aws_key_pair.fleet_key[0].key_name : var.key_pair_name}.pem ec2-user@<instance-public-ip>"
    security_group_id    = aws_security_group.fleet_sg.id
    allowed_ports        = ["22", "80", "443"]
    key_pair_name        = var.create_key_pair ? aws_key_pair.fleet_key[0].key_name : var.key_pair_name
  }
}

# Monitoring and observability
output "monitoring_endpoints" {
  description = "Monitoring and observability endpoints"
  value = {
    cloudwatch_dashboard = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.fleet_dashboard[0].dashboard_name : null
    log_group            = aws_cloudwatch_log_group.fleet_logs.name
    sns_topic            = aws_sns_topic.fleet_notifications.arn
    cpu_alarm            = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
    capacity_alarm       = aws_cloudwatch_metric_alarm.spot_fleet_capacity.alarm_name
  }
}

# Fleet status commands
output "fleet_management_commands" {
  description = "AWS CLI commands for managing the deployed fleets"
  value = {
    check_ec2_fleet_status = "aws ec2 describe-fleets --fleet-ids ${aws_ec2_fleet.main_fleet.id}"
    check_ec2_fleet_instances = "aws ec2 describe-fleet-instances --fleet-id ${aws_ec2_fleet.main_fleet.id}"
    check_spot_fleet_status = "aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids ${aws_spot_fleet_request.main_spot_fleet.id}"
    modify_ec2_fleet_capacity = "aws ec2 modify-fleet --fleet-id ${aws_ec2_fleet.main_fleet.id} --target-capacity-specification TotalTargetCapacity=<new-capacity>"
    cancel_spot_fleet = "aws ec2 cancel-spot-fleet-requests --spot-fleet-request-ids ${aws_spot_fleet_request.main_spot_fleet.id} --terminate-instances"
  }
}

# Resource tags for identification
output "resource_tags" {
  description = "Tags applied to all resources"
  value = local.common_tags
}

# Network configuration summary
output "network_configuration" {
  description = "Network configuration summary"
  value = {
    vpc_id                 = local.vpc_id
    subnet_count          = length(local.subnet_ids)
    availability_zones    = local.availability_zones
    security_group_id     = aws_security_group.fleet_sg.id
    allowed_cidr_blocks   = var.allowed_cidr_blocks
  }
}