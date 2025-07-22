# AWS Region Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Environment Configuration
variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Auto Scaling Group Configuration
variable "instance_type" {
  description = "EC2 instance type for Auto Scaling Group"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = can(regex("^[tm][2-9]+[a-z]*\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type (e.g., t3.micro, m5.large)."
  }
}

variable "min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.min_size >= 0 && var.min_size <= 100
    error_message = "Minimum size must be between 0 and 100."
  }
}

variable "max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_size >= 1 && var.max_size <= 100
    error_message = "Maximum size must be between 1 and 100."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.desired_capacity >= 0 && var.desired_capacity <= 100
    error_message = "Desired capacity must be between 0 and 100."
  }
}

# Scaling Policy Configuration
variable "target_cpu_utilization" {
  description = "Target CPU utilization for target tracking scaling policy"
  type        = number
  default     = 50.0
  
  validation {
    condition     = var.target_cpu_utilization > 0 && var.target_cpu_utilization <= 100
    error_message = "Target CPU utilization must be between 0 and 100."
  }
}

variable "predictive_scaling_buffer_time" {
  description = "Buffer time in seconds for predictive scaling"
  type        = number
  default     = 300
  
  validation {
    condition     = var.predictive_scaling_buffer_time >= 0 && var.predictive_scaling_buffer_time <= 3600
    error_message = "Buffer time must be between 0 and 3600 seconds."
  }
}

variable "predictive_scaling_max_capacity_buffer" {
  description = "Maximum capacity buffer percentage for predictive scaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.predictive_scaling_max_capacity_buffer >= 0 && var.predictive_scaling_max_capacity_buffer <= 100
    error_message = "Maximum capacity buffer must be between 0 and 100 percent."
  }
}

variable "predictive_scaling_mode" {
  description = "Mode for predictive scaling policy (ForecastOnly or ForecastAndScale)"
  type        = string
  default     = "ForecastOnly"
  
  validation {
    condition     = contains(["ForecastOnly", "ForecastAndScale"], var.predictive_scaling_mode)
    error_message = "Predictive scaling mode must be either 'ForecastOnly' or 'ForecastAndScale'."
  }
}

# Instance Configuration
variable "instance_warmup_time" {
  description = "Default instance warmup time in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.instance_warmup_time >= 0 && var.instance_warmup_time <= 3600
    error_message = "Instance warmup time must be between 0 and 3600 seconds."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for instances"
  type        = bool
  default     = true
}

# Networking Configuration
variable "create_vpc" {
  description = "Whether to create a new VPC or use existing one"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID of existing VPC (used when create_vpc is false)"
  type        = string
  default     = ""
}

variable "existing_subnet_ids" {
  description = "List of existing subnet IDs (used when create_vpc is false)"
  type        = list(string)
  default     = []
}

# Resource Naming
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "predictive-scaling"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "Name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# CloudWatch Dashboard
variable "create_dashboard" {
  description = "Whether to create CloudWatch dashboard"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}