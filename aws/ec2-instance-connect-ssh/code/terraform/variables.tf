# Input Variables for EC2 Instance Connect Infrastructure
# This file defines all configurable parameters for the infrastructure deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "ec2-connect"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "instance_type" {
  description = "EC2 instance type for test instances"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type (e.g., t3.micro)."
  }
}

variable "create_private_instance" {
  description = "Whether to create a private instance and Instance Connect Endpoint"
  type        = bool
  default     = true
}

variable "create_cloudtrail" {
  description = "Whether to create CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name for CloudTrail logs (leave empty for auto-generated)"
  type        = string
  default     = ""
  
  validation {
    condition = var.cloudtrail_s3_bucket_name == "" || can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.cloudtrail_s3_bucket_name))
    error_message = "S3 bucket name must be valid: lowercase letters, numbers, and hyphens only."
  }
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed for SSH access to public instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR notation."
  }
}

variable "iam_user_name" {
  description = "Name for the IAM user with Instance Connect permissions (leave empty to skip user creation)"
  type        = string
  default     = ""
  
  validation {
    condition = var.iam_user_name == "" || can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.iam_user_name))
    error_message = "IAM user name must contain only valid characters."
  }
}

variable "create_restrictive_policy" {
  description = "Whether to create resource-specific restrictive IAM policies"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID to use (leave empty to use default VPC)"
  type        = string
  default     = ""
  
  validation {
    condition = var.vpc_id == "" || can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "VPC ID must be empty or a valid VPC identifier."
  }
}

variable "public_subnet_id" {
  description = "Public subnet ID for public instance (leave empty for auto-selection)"
  type        = string
  default     = ""
  
  validation {
    condition = var.public_subnet_id == "" || can(regex("^subnet-[0-9a-f]+$", var.public_subnet_id))
    error_message = "Subnet ID must be empty or a valid subnet identifier."
  }
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet creation (only used if create_private_instance is true)"
  type        = string
  default     = "172.31.64.0/24"
  
  validation {
    condition = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "Private subnet CIDR must be valid IPv4 CIDR notation."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "instance_metadata_options" {
  description = "Configuration for EC2 instance metadata service"
  type = object({
    http_endpoint               = string
    http_tokens                = string
    http_put_response_hop_limit = number
    instance_metadata_tags      = string
  })
  default = {
    http_endpoint               = "enabled"
    http_tokens                = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }
  
  validation {
    condition = contains(["enabled", "disabled"], var.instance_metadata_options.http_endpoint)
    error_message = "HTTP endpoint must be 'enabled' or 'disabled'."
  }
  
  validation {
    condition = contains(["required", "optional"], var.instance_metadata_options.http_tokens)
    error_message = "HTTP tokens must be 'required' or 'optional'."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9\\s_.:/=+\\-@]+$", k)) && can(regex("^[a-zA-Z0-9\\s_.:/=+\\-@]*$", v))
    ])
    error_message = "Tag keys and values must contain only valid characters."
  }
}