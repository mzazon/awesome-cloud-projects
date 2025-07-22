# Input variables for the Terraform Infrastructure as Code demonstration

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "terraform-iac-demo"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use for resources"
  type        = list(string)
  default     = []
  
  # If empty, will use the first 2 AZs available in the region
}

variable "instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.nano", "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3.xlarge", "t3.2xlarge", "m5.large", "m5.xlarge", "m5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "min_capacity" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.min_capacity >= 1 && var.min_capacity <= 10
    error_message = "Minimum capacity must be between 1 and 10."
  }
}

variable "max_capacity" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 4
  
  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 20
    error_message = "Maximum capacity must be between 1 and 20."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.desired_capacity >= 1
    error_message = "Desired capacity must be at least 1."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the Application Load Balancer"
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Enable access logging for the Application Load Balancer"
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/"
  
  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS listener (optional)"
  type        = string
  default     = ""
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets (additional cost)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 0 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 0 and 35."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9\\s\\-_.:/=+@]*$", k))])
    error_message = "Tag keys must contain only alphanumeric characters, spaces, and the following characters: - _ . : / = + @"
  }
}