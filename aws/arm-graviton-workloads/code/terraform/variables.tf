# Variables for AWS Graviton Workload Infrastructure
# This file defines all configurable parameters for the Graviton workload deployment

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-west-2, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "graviton-workload"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair to use for SSH access. If not provided, a new key pair will be created."
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the instances via SSH and HTTP"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

variable "instance_ami_id" {
  description = "AMI ID for EC2 instances. If not provided, will use the latest Amazon Linux 2 AMI."
  type        = string
  default     = ""
}

variable "x86_instance_type" {
  description = "EC2 instance type for x86 baseline instance"
  type        = string
  default     = "c6i.large"
  
  validation {
    condition = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.x86_instance_type))
    error_message = "Instance type must be in the format: c6i.large, m5.xlarge, etc."
  }
}

variable "arm_instance_type" {
  description = "EC2 instance type for ARM Graviton instances"
  type        = string
  default     = "c7g.large"
  
  validation {
    condition = can(regex("^[a-z0-9]+g\\.[a-z0-9]+$", var.arm_instance_type))
    error_message = "ARM instance type must contain 'g' in the family name (e.g., c7g.large, m7g.xlarge)."
  }
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
  
  validation {
    condition = var.asg_min_size >= 0 && var.asg_min_size <= 10
    error_message = "ASG minimum size must be between 0 and 10."
  }
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 3
  
  validation {
    condition = var.asg_max_size >= 1 && var.asg_max_size <= 20
    error_message = "ASG maximum size must be between 1 and 20."
  }
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition = var.asg_desired_capacity >= 1 && var.asg_desired_capacity <= 10
    error_message = "ASG desired capacity must be between 1 and 10."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = true
}

variable "cost_alert_threshold" {
  description = "Cost threshold in USD for CloudWatch billing alarm"
  type        = number
  default     = 50.0
  
  validation {
    condition = var.cost_alert_threshold > 0 && var.cost_alert_threshold <= 1000
    error_message = "Cost alert threshold must be between 1 and 1000 USD."
  }
}

variable "create_nat_gateway" {
  description = "Whether to create a NAT Gateway for private subnets"
  type        = bool
  default     = false
}

variable "enable_ssm_session_manager" {
  description = "Enable AWS Systems Manager Session Manager for secure shell access"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}