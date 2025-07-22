# Variables for AWS Cloud9 developer environments infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cloud9-dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cloud9_environment_name" {
  description = "Name for the Cloud9 environment"
  type        = string
  default     = ""
}

variable "cloud9_description" {
  description = "Description for the Cloud9 environment"
  type        = string
  default     = "Shared development environment for team collaboration"
}

variable "cloud9_instance_type" {
  description = "EC2 instance type for the Cloud9 environment"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition = can(regex("^(t3|t4g|m5|m6i|c5|c6i)\\.(nano|micro|small|medium|large|xlarge|2xlarge)$", var.cloud9_instance_type))
    error_message = "Instance type must be a valid EC2 instance type suitable for development work."
  }
}

variable "cloud9_auto_stop_minutes" {
  description = "Number of minutes of inactivity before Cloud9 automatically stops the instance"
  type        = number
  default     = 60
  
  validation {
    condition     = var.cloud9_auto_stop_minutes >= 30 && var.cloud9_auto_stop_minutes <= 20160
    error_message = "Auto stop minutes must be between 30 and 20160 (14 days)."
  }
}

variable "cloud9_image_id" {
  description = "Amazon Machine Image ID for the Cloud9 environment"
  type        = string
  default     = "amazonlinux-2023-x86_64"
  
  validation {
    condition = contains([
      "amazonlinux-2023-x86_64",
      "amazonlinux-2-x86_64",
      "ubuntu-18.04-x86_64",
      "ubuntu-22.04-x86_64"
    ], var.cloud9_image_id)
    error_message = "Image ID must be one of the supported Cloud9 images."
  }
}

variable "subnet_id" {
  description = "Subnet ID where the Cloud9 environment will be created. If not provided, uses default subnet"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID where the Cloud9 environment will be created. If not provided, uses default VPC"
  type        = string
  default     = ""
}

variable "codecommit_repository_name" {
  description = "Name for the CodeCommit repository"
  type        = string
  default     = ""
}

variable "codecommit_repository_description" {
  description = "Description for the CodeCommit repository"
  type        = string
  default     = "Team development repository for Cloud9 environment"
}

variable "enable_codecommit" {
  description = "Whether to create a CodeCommit repository for the development team"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_dashboard" {
  description = "Whether to create a CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = ""
}

variable "team_member_arns" {
  description = "List of IAM user ARNs to add as team members to the Cloud9 environment"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.team_member_arns : can(regex("^arn:aws:iam::[0-9]{12}:user/.+", arn))
    ])
    error_message = "All team member ARNs must be valid IAM user ARNs."
  }
}

variable "team_member_permissions" {
  description = "Permissions level for team members (read-only or read-write)"
  type        = string
  default     = "read-write"
  
  validation {
    condition     = contains(["read-only", "read-write"], var.team_member_permissions)
    error_message = "Team member permissions must be either 'read-only' or 'read-write'."
  }
}

variable "create_development_policy" {
  description = "Whether to create a custom IAM policy for development permissions"
  type        = bool
  default     = true
}

variable "development_policy_name" {
  description = "Name for the custom development IAM policy"
  type        = string
  default     = ""
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}