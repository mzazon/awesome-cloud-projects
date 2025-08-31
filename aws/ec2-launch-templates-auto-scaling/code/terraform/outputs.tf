# outputs.tf
# Output values for EC2 Launch Templates and Auto Scaling infrastructure

output "launch_template_id" {
  description = "ID of the created launch template"
  value       = aws_launch_template.web_server.id
}

output "launch_template_name" {
  description = "Name of the created launch template"
  value       = aws_launch_template.web_server.name
}

output "launch_template_latest_version" {
  description = "Latest version number of the launch template"
  value       = aws_launch_template.web_server.latest_version
}

output "auto_scaling_group_id" {
  description = "ID of the Auto Scaling group"
  value       = aws_autoscaling_group.web_servers.id
}

output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling group"
  value       = aws_autoscaling_group.web_servers.name
}

output "auto_scaling_group_arn" {
  description = "ARN of the Auto Scaling group"
  value       = aws_autoscaling_group.web_servers.arn
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.web_server.id
}

output "security_group_name" {
  description = "Name of the security group"
  value       = aws_security_group.web_server.name
}

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

output "scaling_policy_name" {
  description = "Name of the target tracking scaling policy"
  value       = aws_autoscaling_policy.cpu_target_tracking.name
}

output "scaling_policy_arn" {
  description = "ARN of the target tracking scaling policy"
  value       = aws_autoscaling_policy.cpu_target_tracking.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.auto_scaling_dashboard.dashboard_name}"
}

output "vpc_id" {
  description = "ID of the VPC where resources are deployed"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "IDs of the subnets where Auto Scaling group instances are deployed"
  value       = data.aws_subnets.default.ids
}

output "ami_id" {
  description = "ID of the Amazon Linux 2 AMI used for instances"
  value       = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  description = "Name of the Amazon Linux 2 AMI used for instances"
  value       = data.aws_ami.amazon_linux.name
}

# Conditional output for instance public IPs (only if public IPs are enabled)
output "instance_public_ips" {
  description = "Public IP addresses of running instances (only available if public IPs are enabled)"
  value = var.enable_public_ip ? [
    for instance in data.aws_instances.asg_instances.public_ips : instance
  ] : ["Public IPs disabled"]
  depends_on = [aws_autoscaling_group.web_servers]
}

output "instance_private_ips" {
  description = "Private IP addresses of running instances"
  value       = data.aws_instances.asg_instances.private_ips
  depends_on  = [aws_autoscaling_group.web_servers]
}

output "web_application_urls" {
  description = "URLs to access the web application on running instances"
  value = var.enable_public_ip ? [
    for ip in data.aws_instances.asg_instances.public_ips : "http://${ip}"
  ] : ["Public access disabled - use private IPs within VPC"]
  depends_on = [aws_autoscaling_group.web_servers]
}

# Data source to get current instances in the Auto Scaling group
data "aws_instances" "asg_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.web_servers.name]
  }
  
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
  
  depends_on = [aws_autoscaling_group.web_servers]
}

output "current_instance_count" {
  description = "Current number of running instances in the Auto Scaling group"
  value       = length(data.aws_instances.asg_instances.ids)
  depends_on  = [aws_autoscaling_group.web_servers]
}

output "current_instance_ids" {
  description = "Instance IDs of currently running instances"
  value       = data.aws_instances.asg_instances.ids
  depends_on  = [aws_autoscaling_group.web_servers]
}

# Configuration summary for validation
output "configuration_summary" {
  description = "Summary of the Auto Scaling configuration"
  value = {
    auto_scaling_group_name    = aws_autoscaling_group.web_servers.name
    launch_template_name       = aws_launch_template.web_server.name
    instance_type             = var.instance_type
    min_size                  = var.min_size
    max_size                  = var.max_size
    desired_capacity          = var.desired_capacity
    target_cpu_utilization    = var.target_cpu_utilization
    health_check_grace_period = var.health_check_grace_period
    availability_zones        = data.aws_subnets.default.ids
    security_group_id         = aws_security_group.web_server.id
    public_ip_enabled         = var.enable_public_ip
    detailed_monitoring       = var.enable_detailed_monitoring
  }
}

# Validation commands for manual testing
output "validation_commands" {
  description = "AWS CLI commands to validate the deployment"
  value = {
    check_asg_status = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.web_servers.name} --region ${var.aws_region}"
    check_instances  = "aws ec2 describe-instances --filters 'Name=tag:aws:autoscaling:groupName,Values=${aws_autoscaling_group.web_servers.name}' --region ${var.aws_region}"
    check_lt_details = "aws ec2 describe-launch-templates --launch-template-ids ${aws_launch_template.web_server.id} --region ${var.aws_region}"
    check_scaling_policies = "aws autoscaling describe-policies --auto-scaling-group-name ${aws_autoscaling_group.web_servers.name} --region ${var.aws_region}"
  }
}