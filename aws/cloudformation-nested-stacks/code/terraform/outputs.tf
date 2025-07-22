# ==============================================================================
# Outputs for Modular Multi-Tier Architecture
# These outputs provide important information about the deployed infrastructure
# and enable integration with other systems and monitoring tools.
# ==============================================================================

# ==============================================================================
# Network Layer Outputs
# ==============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.main.arn
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "nat_gateway_public_ips" {
  description = "Public IP addresses of the NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "availability_zones" {
  description = "Availability zones used by subnets"
  value       = data.aws_availability_zones.available.names
}

# ==============================================================================
# Security Layer Outputs
# ==============================================================================

output "alb_security_group_id" {
  description = "ID of the Application Load Balancer security group"
  value       = aws_security_group.alb.id
}

output "application_security_group_id" {
  description = "ID of the application security group"
  value       = aws_security_group.application.id
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = aws_security_group.database.id
}

output "bastion_security_group_id" {
  description = "ID of the bastion security group"
  value       = aws_security_group.bastion.id
}

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

output "rds_monitoring_role_arn" {
  description = "ARN of the RDS monitoring IAM role"
  value       = aws_iam_role.rds_monitoring_role.arn
}

# ==============================================================================
# Application Layer Outputs
# ==============================================================================

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.application.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.application.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.application.zone_id
}

output "application_url" {
  description = "URL to access the application"
  value       = "http://${aws_lb.application.dns_name}"
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.application.arn
}

output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.application.name
}

output "auto_scaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.application.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.application.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.application.latest_version
}

# ==============================================================================
# Database Layer Outputs
# ==============================================================================

output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.database.endpoint
}

output "database_port" {
  description = "RDS instance port"
  value       = aws_db_instance.database.port
}

output "database_name" {
  description = "Name of the database"
  value       = aws_db_instance.database.db_name
}

output "database_username" {
  description = "Master username for the database"
  value       = aws_db_instance.database.username
  sensitive   = true
}

output "database_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.database.arn
}

output "database_id" {
  description = "ID of the RDS instance"
  value       = aws_db_instance.database.id
}

output "database_secret_arn" {
  description = "ARN of the database secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.database.arn
}

output "database_secret_name" {
  description = "Name of the database secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.database.name
}

output "database_subnet_group_name" {
  description = "Name of the database subnet group"
  value       = aws_db_subnet_group.database.name
}

# ==============================================================================
# Monitoring and Logging Outputs
# ==============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.arn
}

# ==============================================================================
# Environment and Configuration Outputs
# ==============================================================================

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_identifier" {
  description = "Unique identifier for this deployment"
  value       = random_string.suffix.result
}

output "name_prefix" {
  description = "Common naming prefix used for resources"
  value       = local.name_prefix
}

# ==============================================================================
# Resource Tags Output
# ==============================================================================

output "common_tags" {
  description = "Common tags applied to all resources"
  value = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "CloudFormation-Nested-Stacks-Demo"
  }
}

# ==============================================================================
# Architecture Summary
# ==============================================================================

output "architecture_summary" {
  description = "Summary of the deployed architecture"
  value = {
    vpc = {
      id         = aws_vpc.main.id
      cidr_block = aws_vpc.main.cidr_block
    }
    subnets = {
      public_count  = length(aws_subnet.public)
      private_count = length(aws_subnet.private)
      public_cidrs  = aws_subnet.public[*].cidr_block
      private_cidrs = aws_subnet.private[*].cidr_block
    }
    load_balancer = {
      dns_name = aws_lb.application.dns_name
      url      = "http://${aws_lb.application.dns_name}"
    }
    auto_scaling = {
      min_size         = aws_autoscaling_group.application.min_size
      max_size         = aws_autoscaling_group.application.max_size
      desired_capacity = aws_autoscaling_group.application.desired_capacity
    }
    database = {
      endpoint      = aws_db_instance.database.endpoint
      engine        = aws_db_instance.database.engine
      engine_version = aws_db_instance.database.engine_version
      instance_class = aws_db_instance.database.instance_class
      multi_az      = aws_db_instance.database.multi_az
    }
    environment_config = local.current_config
  }
}

# ==============================================================================
# Connection Information
# ==============================================================================

output "connection_info" {
  description = "Information for connecting to deployed resources"
  value = {
    application_url = "http://${aws_lb.application.dns_name}"
    health_check_url = "http://${aws_lb.application.dns_name}/health"
    database_connection = {
      endpoint = aws_db_instance.database.endpoint
      port     = aws_db_instance.database.port
      database = aws_db_instance.database.db_name
      username = aws_db_instance.database.username
      secret_arn = aws_secretsmanager_secret.database.arn
    }
    monitoring = {
      log_group = aws_cloudwatch_log_group.application.name
    }
  }
  sensitive = false
}