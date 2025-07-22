# Variables for EC2 Fleet Management configuration

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1' or similar."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.environment))
    error_message = "Environment name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "ec2-fleet-demo"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "use_default_vpc" {
  description = "Whether to use the default VPC and subnets"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID to use for resources (ignored if use_default_vpc is true)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs to use for fleet instances (ignored if use_default_vpc is true)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid."
  }
}

variable "instance_types" {
  description = "List of instance types for fleet diversification"
  type        = list(string)
  default     = ["t3.micro", "t3.small", "t3.nano"]
  
  validation {
    condition = length(var.instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

variable "ec2_fleet_target_capacity" {
  description = "Total target capacity for EC2 Fleet"
  type        = number
  default     = 6
  
  validation {
    condition = var.ec2_fleet_target_capacity > 0 && var.ec2_fleet_target_capacity <= 100
    error_message = "EC2 Fleet target capacity must be between 1 and 100."
  }
}

variable "ec2_fleet_on_demand_capacity" {
  description = "On-Demand target capacity for EC2 Fleet"
  type        = number
  default     = 2
  
  validation {
    condition = var.ec2_fleet_on_demand_capacity >= 0
    error_message = "EC2 Fleet On-Demand capacity must be non-negative."
  }
}

variable "ec2_fleet_spot_capacity" {
  description = "Spot target capacity for EC2 Fleet"
  type        = number
  default     = 4
  
  validation {
    condition = var.ec2_fleet_spot_capacity >= 0
    error_message = "EC2 Fleet Spot capacity must be non-negative."
  }
}

variable "spot_fleet_target_capacity" {
  description = "Target capacity for Spot Fleet"
  type        = number
  default     = 3
  
  validation {
    condition = var.spot_fleet_target_capacity > 0 && var.spot_fleet_target_capacity <= 50
    error_message = "Spot Fleet target capacity must be between 1 and 50."
  }
}

variable "spot_max_price" {
  description = "Maximum price for Spot instances (per hour)"
  type        = string
  default     = "0.10"
  
  validation {
    condition = can(regex("^[0-9]+\\.?[0-9]*$", var.spot_max_price))
    error_message = "Spot max price must be a valid decimal number."
  }
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair to use for instances (will be created if not exists)"
  type        = string
  default     = ""
}

variable "create_key_pair" {
  description = "Whether to create a new key pair"
  type        = bool
  default     = true
}

variable "create_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "enable_termination_protection" {
  description = "Enable termination protection for fleet instances"
  type        = bool
  default     = false
}

variable "user_data_script" {
  description = "User data script to run on instance startup"
  type        = string
  default     = ""
}

variable "additional_security_group_rules" {
  description = "Additional security group rules to add"
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = []
}

variable "fleet_allocation_strategy" {
  description = "Allocation strategy for Spot Fleet"
  type        = string
  default     = "capacity-optimized"
  
  validation {
    condition = contains(["capacity-optimized", "diversified", "lowest-price"], var.fleet_allocation_strategy)
    error_message = "Fleet allocation strategy must be one of: capacity-optimized, diversified, lowest-price."
  }
}

variable "replace_unhealthy_instances" {
  description = "Whether to replace unhealthy instances automatically"
  type        = bool
  default     = true
}

variable "resource_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}