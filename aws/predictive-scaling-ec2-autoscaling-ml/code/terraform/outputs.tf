# VPC and Networking Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].cidr_block : ""
}

output "subnet_ids" {
  description = "IDs of the subnets"
  value       = var.create_vpc ? aws_subnet.public[*].id : var.existing_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = var.create_vpc ? aws_internet_gateway.main[0].id : ""
}

output "security_group_id" {
  description = "ID of the security group for EC2 instances"
  value       = aws_security_group.ec2.id
}

# Auto Scaling Group Outputs
output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.arn
}

output "autoscaling_group_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.min_size
}

output "autoscaling_group_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.max_size
}

output "autoscaling_group_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  value       = aws_autoscaling_group.main.desired_capacity
}

# Launch Template Outputs
output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.main.id
}

output "launch_template_latest_version" {
  description = "Latest version of the Launch Template"
  value       = aws_launch_template.main.latest_version
}

output "launch_template_name" {
  description = "Name of the Launch Template"
  value       = aws_launch_template.main.name
}

# IAM Outputs
output "iam_role_name" {
  description = "Name of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.arn
}

# Scaling Policy Outputs
output "target_tracking_policy_name" {
  description = "Name of the target tracking scaling policy"
  value       = aws_autoscaling_policy.target_tracking.name
}

output "target_tracking_policy_arn" {
  description = "ARN of the target tracking scaling policy"
  value       = aws_autoscaling_policy.target_tracking.arn
}

output "predictive_scaling_policy_name" {
  description = "Name of the predictive scaling policy"
  value       = aws_autoscaling_policy.predictive_scaling.name
}

output "predictive_scaling_policy_arn" {
  description = "ARN of the predictive scaling policy"
  value       = aws_autoscaling_policy.predictive_scaling.arn
}

# CloudWatch Outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_name : ""
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value = var.create_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main[0].dashboard_name}" : ""
}

output "high_cpu_alarm_name" {
  description = "Name of the high CPU CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
}

output "low_cpu_alarm_name" {
  description = "Name of the low CPU CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.low_cpu.alarm_name
}

# Configuration Outputs
output "target_cpu_utilization" {
  description = "Target CPU utilization for scaling policies"
  value       = var.target_cpu_utilization
}

output "predictive_scaling_mode" {
  description = "Mode of the predictive scaling policy"
  value       = var.predictive_scaling_mode
}

output "predictive_scaling_buffer_time" {
  description = "Buffer time for predictive scaling in seconds"
  value       = var.predictive_scaling_buffer_time
}

# Instance Information
output "instance_type" {
  description = "EC2 instance type used in the Auto Scaling Group"
  value       = var.instance_type
}

output "ami_id" {
  description = "AMI ID used for EC2 instances"
  value       = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  description = "Name of the AMI used for EC2 instances"
  value       = data.aws_ami.amazon_linux.name
}

# Useful Commands Output
output "useful_commands" {
  description = "Useful AWS CLI commands for monitoring and management"
  value = {
    view_asg_activities = "aws autoscaling describe-scaling-activities --auto-scaling-group-name ${aws_autoscaling_group.main.name} --max-items 10"
    view_asg_instances  = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name ${aws_autoscaling_group.main.name} --query 'AutoScalingGroups[0].Instances'"
    get_predictive_forecast = "aws autoscaling get-predictive-scaling-forecast --policy-arn ${aws_autoscaling_policy.predictive_scaling.arn}"
    view_scaling_policies = "aws autoscaling describe-policies --auto-scaling-group-name ${aws_autoscaling_group.main.name}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_created                    = var.create_vpc
    autoscaling_group_name        = aws_autoscaling_group.main.name
    target_tracking_policy_created = true
    predictive_scaling_policy_created = true
    cloudwatch_dashboard_created  = var.create_dashboard
    security_group_created        = true
    launch_template_created       = true
    iam_resources_created         = true
  }
}

# Validation URLs
output "validation_urls" {
  description = "URLs for validating the deployment"
  value = {
    auto_scaling_console = "https://${var.aws_region}.console.aws.amazon.com/ec2/v2/home?region=${var.aws_region}#AutoScalingGroupDetails:id=${aws_autoscaling_group.main.name}"
    cloudwatch_console = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}"
    ec2_instances_console = "https://${var.aws_region}.console.aws.amazon.com/ec2/v2/home?region=${var.aws_region}#Instances:tag:aws:autoscaling:groupName=${aws_autoscaling_group.main.name}"
  }
}