# Output values for the Terraform Infrastructure as Code demonstration
# These outputs provide essential information for verification, integration, and troubleshooting

# ============================================================================
# NETWORKING OUTPUTS
# ============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "availability_zones" {
  description = "Availability zones used for the subnets"
  value       = local.availability_zones
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

# ============================================================================
# SECURITY GROUP OUTPUTS
# ============================================================================

output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group"
  value       = aws_security_group.alb.id
}

output "web_security_group_id" {
  description = "ID of the web server security group"
  value       = aws_security_group.web.id
}

# ============================================================================
# LOAD BALANCER OUTPUTS
# ============================================================================

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.web.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.web.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.web.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.web.arn
}

output "alb_url" {
  description = "URL to access the application through the load balancer"
  value       = "http://${aws_lb.web.dns_name}"
}

output "alb_https_url" {
  description = "HTTPS URL to access the application (if SSL certificate is configured)"
  value       = var.ssl_certificate_arn != "" ? "https://${aws_lb.web.dns_name}" : "HTTPS not configured - no SSL certificate provided"
}

# ============================================================================
# AUTO SCALING AND COMPUTE OUTPUTS
# ============================================================================

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.web.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.web.latest_version
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.arn
}

output "autoscaling_group_min_size" {
  description = "Minimum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.min_size
}

output "autoscaling_group_max_size" {
  description = "Maximum size of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.max_size
}

output "autoscaling_group_desired_capacity" {
  description = "Desired capacity of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.desired_capacity
}

# ============================================================================
# CLOUDWATCH OUTPUTS
# ============================================================================

output "cloudwatch_alarm_high_cpu_name" {
  description = "Name of the high CPU CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
}

output "cloudwatch_alarm_low_cpu_name" {
  description = "Name of the low CPU CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.low_cpu.alarm_name
}

# ============================================================================
# S3 BUCKET OUTPUTS (if logging is enabled)
# ============================================================================

output "alb_logs_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs"
  value       = var.enable_logging ? aws_s3_bucket.alb_logs[0].bucket : "Logging not enabled"
}

output "alb_logs_bucket_arn" {
  description = "ARN of the S3 bucket for ALB access logs"
  value       = var.enable_logging ? aws_s3_bucket.alb_logs[0].arn : "Logging not enabled"
}

# ============================================================================
# RESOURCE IDENTIFICATION OUTPUTS
# ============================================================================

output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "resource_name_prefix" {
  description = "Prefix used for naming all resources"
  value       = local.name_prefix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# INSTANCE INFORMATION OUTPUTS
# ============================================================================

output "instance_type" {
  description = "EC2 instance type used for web servers"
  value       = var.instance_type
}

output "ami_id" {
  description = "AMI ID used for the EC2 instances"
  value       = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  description = "Name of the AMI used for the EC2 instances"
  value       = data.aws_ami.amazon_linux.name
}

# ============================================================================
# VALIDATION AND TESTING OUTPUTS
# ============================================================================

output "health_check_url" {
  description = "URL for health check testing"
  value       = "http://${aws_lb.web.dns_name}${var.health_check_path}"
}

output "terraform_state_summary" {
  description = "Summary of key Terraform state information"
  value = {
    vpc_id              = aws_vpc.main.id
    public_subnets      = length(aws_subnet.public)
    load_balancer_dns   = aws_lb.web.dns_name
    autoscaling_group   = aws_autoscaling_group.web.name
    target_group        = aws_lb_target_group.web.name
    security_groups     = [aws_security_group.alb.id, aws_security_group.web.id]
    resource_prefix     = local.name_prefix
  }
}

# ============================================================================
# COST AND RESOURCE TRACKING OUTPUTS
# ============================================================================

output "estimated_monthly_cost_components" {
  description = "Breakdown of estimated monthly costs for major components"
  value = {
    alb_monthly_usd               = "~$16.20 (ALB fixed cost)"
    ec2_instances_monthly_usd     = "~$${var.desired_capacity * 8.50} (${var.desired_capacity} x ${var.instance_type})"
    data_transfer_monthly_usd     = "~$9.00 per 100GB (estimate)"
    cloudwatch_alarms_monthly_usd = "~$0.20 (2 alarms)"
    s3_storage_monthly_usd        = var.enable_logging ? "~$0.50 (logs storage)" : "$0 (logging disabled)"
    total_estimated_monthly_usd   = "~$${16.20 + (var.desired_capacity * 8.50) + 9.00 + 0.20 + (var.enable_logging ? 0.50 : 0)}"
  }
}

output "resource_count_summary" {
  description = "Summary of resources created by this Terraform configuration"
  value = {
    vpc_resources           = 1
    subnets                = length(aws_subnet.public)
    security_groups        = 2
    load_balancer          = 1
    target_groups          = 1
    launch_templates       = 1
    autoscaling_groups     = 1
    cloudwatch_alarms      = 2
    s3_buckets            = var.enable_logging ? 1 : 0
    total_major_resources = 9 + length(aws_subnet.public) + (var.enable_logging ? 1 : 0)
  }
}