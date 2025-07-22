# outputs.tf - Output values for the Elastic Load Balancing infrastructure

# VPC and Network Information
output "vpc_id" {
  description = "ID of the VPC where resources are deployed"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for load balancer deployment"
  value       = local.subnet_ids
}

output "availability_zones" {
  description = "List of availability zones where resources are deployed"
  value       = data.aws_availability_zones.available.names
}

# Load Balancer Information
output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.alb.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.alb.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.alb.zone_id
}

output "alb_url" {
  description = "Full URL of the Application Load Balancer"
  value       = "http://${aws_lb.alb.dns_name}"
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.nlb.arn
}

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.nlb.dns_name
}

output "nlb_zone_id" {
  description = "Zone ID of the Network Load Balancer"
  value       = aws_lb.nlb.zone_id
}

output "nlb_url" {
  description = "Full URL of the Network Load Balancer"
  value       = "http://${aws_lb.nlb.dns_name}"
}

# Target Group Information
output "alb_target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.alb.arn
}

output "alb_target_group_name" {
  description = "Name of the ALB target group"
  value       = aws_lb_target_group.alb.name
}

output "nlb_target_group_arn" {
  description = "ARN of the NLB target group"
  value       = aws_lb_target_group.nlb.arn
}

output "nlb_target_group_name" {
  description = "Name of the NLB target group"
  value       = aws_lb_target_group.nlb.name
}

# Listener Information
output "alb_listener_arn" {
  description = "ARN of the ALB HTTP listener"
  value       = aws_lb_listener.alb_http.arn
}

output "nlb_listener_arn" {
  description = "ARN of the NLB TCP listener"
  value       = aws_lb_listener.nlb_tcp.arn
}

# EC2 Instance Information
output "instance_ids" {
  description = "List of EC2 instance IDs"
  value       = aws_instance.web[*].id
}

output "instance_public_ips" {
  description = "List of public IP addresses of EC2 instances"
  value       = aws_instance.web[*].public_ip
}

output "instance_private_ips" {
  description = "List of private IP addresses of EC2 instances"
  value       = aws_instance.web[*].private_ip
}

output "instance_dns_names" {
  description = "List of public DNS names of EC2 instances"
  value       = aws_instance.web[*].public_dns
}

# Security Group Information
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "nlb_security_group_id" {
  description = "ID of the NLB security group"
  value       = aws_security_group.nlb.id
}

output "ec2_security_group_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.ec2.id
}

# Testing Information
output "test_commands" {
  description = "Commands to test the load balancers"
  value = {
    alb_test = "curl -s http://${aws_lb.alb.dns_name}"
    nlb_test = "curl -s http://${aws_lb.nlb.dns_name}"
    alb_load_test = "for i in {1..10}; do curl -s http://${aws_lb.alb.dns_name} | grep 'Instance ID'; done"
    nlb_load_test = "for i in {1..10}; do curl -s http://${aws_lb.nlb.dns_name} | grep 'Instance ID'; done"
  }
}

# Health Check Information
output "health_check_urls" {
  description = "Health check URLs for the load balancers"
  value = {
    alb_health = "http://${aws_lb.alb.dns_name}/health"
    nlb_health = "http://${aws_lb.nlb.dns_name}/health"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the infrastructure (USD)"
  value = {
    alb_cost = "~$16.20 (ALB + data processing)"
    nlb_cost = "~$16.20 (NLB + data processing)"
    ec2_cost = "~$${var.instance_count * 8.46} (t3.micro instances)"
    total_estimate = "~$${32.40 + (var.instance_count * 8.46)} per month"
  }
}

# Project Information
output "project_name" {
  description = "Name of the project"
  value       = local.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = local.random_suffix
}

# Summary Output
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    project_name = local.project_name
    environment = var.environment
    region = var.aws_region
    vpc_id = local.vpc_id
    instance_count = var.instance_count
    alb_url = "http://${aws_lb.alb.dns_name}"
    nlb_url = "http://${aws_lb.nlb.dns_name}"
    test_command = "curl -s http://${aws_lb.alb.dns_name}"
  }
}