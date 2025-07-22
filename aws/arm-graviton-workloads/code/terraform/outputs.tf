# Outputs for AWS Graviton Workload Infrastructure
# This file defines all output values that will be displayed after deployment

# Instance Information
output "x86_instance_id" {
  description = "ID of the x86 baseline instance"
  value       = aws_instance.x86_baseline.id
}

output "arm_instance_id" {
  description = "ID of the ARM Graviton instance"
  value       = aws_instance.arm_graviton.id
}

output "x86_instance_public_ip" {
  description = "Public IP address of the x86 baseline instance"
  value       = aws_instance.x86_baseline.public_ip
}

output "arm_instance_public_ip" {
  description = "Public IP address of the ARM Graviton instance"
  value       = aws_instance.arm_graviton.public_ip
}

output "x86_instance_private_ip" {
  description = "Private IP address of the x86 baseline instance"
  value       = aws_instance.x86_baseline.private_ip
}

output "arm_instance_private_ip" {
  description = "Private IP address of the ARM Graviton instance"
  value       = aws_instance.arm_graviton.private_ip
}

# Load Balancer Information
output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.graviton_demo.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.graviton_demo.arn
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.graviton_demo.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.graviton_demo.arn
}

# Auto Scaling Group Information
output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.arm_graviton.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.arm_graviton.arn
}

output "launch_template_id" {
  description = "ID of the launch template for ARM instances"
  value       = aws_launch_template.arm_graviton.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.arm_graviton.latest_version
}

# Security Information
output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.graviton_demo.id
}

output "key_pair_name" {
  description = "Name of the EC2 key pair"
  value       = var.key_pair_name != "" ? var.key_pair_name : aws_key_pair.graviton_demo[0].key_name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for EC2 instances"
  value       = aws_iam_role.ec2_graviton_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_graviton_profile.name
}

# Monitoring Information
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.graviton_performance.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.graviton_performance.dashboard_name}"
}

output "cost_alarm_name" {
  description = "Name of the cost monitoring alarm"
  value       = aws_cloudwatch_metric_alarm.cost_alert.alarm_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost alerts"
  value       = aws_sns_topic.cost_alerts.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.graviton_demo.name
}

# S3 Bucket Information
output "alb_logs_bucket" {
  description = "Name of the S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.bucket
}

output "alb_logs_bucket_arn" {
  description = "ARN of the S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.arn
}

# Network Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = data.aws_subnets.default.ids
}

# AMI Information
output "x86_ami_id" {
  description = "AMI ID used for x86 instances"
  value       = var.instance_ami_id != "" ? var.instance_ami_id : data.aws_ami.amazon_linux_x86.id
}

output "arm_ami_id" {
  description = "AMI ID used for ARM instances"
  value       = var.instance_ami_id != "" ? var.instance_ami_id : data.aws_ami.amazon_linux_arm.id
}

# Access Information
output "web_application_urls" {
  description = "URLs to access the web applications"
  value = {
    x86_instance    = "http://${aws_instance.x86_baseline.public_ip}"
    arm_instance    = "http://${aws_instance.arm_graviton.public_ip}"
    load_balancer   = "http://${aws_lb.graviton_demo.dns_name}"
  }
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    x86_instance = "ssh -i ${var.key_pair_name != "" ? var.key_pair_name : "${local.name_prefix}-keypair"}.pem ec2-user@${aws_instance.x86_baseline.public_ip}"
    arm_instance = "ssh -i ${var.key_pair_name != "" ? var.key_pair_name : "${local.name_prefix}-keypair"}.pem ec2-user@${aws_instance.arm_graviton.public_ip}"
  }
}

# Performance Testing Commands
output "benchmark_commands" {
  description = "Commands to run performance benchmarks"
  value = {
    x86_benchmark = "ssh -i ${var.key_pair_name != "" ? var.key_pair_name : "${local.name_prefix}-keypair"}.pem ec2-user@${aws_instance.x86_baseline.public_ip} 'sudo /home/ec2-user/benchmark.sh'"
    arm_benchmark = "ssh -i ${var.key_pair_name != "" ? var.key_pair_name : "${local.name_prefix}-keypair"}.pem ec2-user@${aws_instance.arm_graviton.public_ip} 'sudo /home/ec2-user/benchmark.sh'"
  }
}

# Cost Comparison Information
output "cost_comparison" {
  description = "Cost comparison between x86 and ARM instances"
  value = {
    x86_instance_type    = var.x86_instance_type
    arm_instance_type    = var.arm_instance_type
    estimated_hourly_savings = "ARM instances typically provide 15-40% cost savings over comparable x86 instances"
    pricing_note        = "Check AWS pricing calculator for current rates in your region"
  }
}

# Regional Information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "availability_zones" {
  description = "Available availability zones in the region"
  value       = data.aws_availability_zones.available.names
}

# Resource Naming
output "resource_name_prefix" {
  description = "Prefix used for naming resources"
  value       = local.name_prefix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Private Key Information (if generated)
output "private_key_file" {
  description = "Location of the private key file (if generated)"
  value       = var.key_pair_name == "" ? "${path.module}/${local.name_prefix}-keypair.pem" : "Using existing key pair: ${var.key_pair_name}"
}

# System Manager Session Manager Commands (if enabled)
output "ssm_session_commands" {
  description = "AWS Systems Manager Session Manager commands"
  value = var.enable_ssm_session_manager ? {
    x86_instance = "aws ssm start-session --target ${aws_instance.x86_baseline.id}"
    arm_instance = "aws ssm start-session --target ${aws_instance.arm_graviton.id}"
  } : {}
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_instances = "aws ec2 describe-instances --instance-ids ${aws_instance.x86_baseline.id} ${aws_instance.arm_graviton.id} --query 'Reservations[].Instances[].[InstanceId,InstanceType,Architecture,State.Name]' --output table"
    check_target_group = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.graviton_demo.arn}"
    check_asg = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.arm_graviton.name}"
    test_load_balancer = "curl -s http://${aws_lb.graviton_demo.dns_name}"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    step1 = "Wait 5-10 minutes for instances to fully initialize"
    step2 = "Test web applications using the provided URLs"
    step3 = "Run performance benchmarks using the provided commands"
    step4 = "Monitor performance metrics in the CloudWatch dashboard"
    step5 = "Compare costs using AWS Cost Explorer"
  }
}