# Input variables for EFS mounting strategies configuration

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "efs-mounting-strategies"
}

variable "vpc_id" {
  description = "VPC ID where resources will be created. If not provided, will use default VPC"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets. If not provided, will use default VPC subnets"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones for EFS mount targets. Used when subnet_ids is not provided"
  type        = list(string)
  default     = []
}

variable "efs_performance_mode" {
  description = "EFS performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"
  
  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "EFS performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode (bursting or provisioned)"
  type        = string
  default     = "provisioned"
  
  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s (only used when throughput_mode is 'provisioned')"
  type        = number
  default     = 100
  
  validation {
    condition     = var.efs_provisioned_throughput >= 1 && var.efs_provisioned_throughput <= 1024
    error_message = "Provisioned throughput must be between 1 and 1024 MiB/s."
  }
}

variable "efs_encryption" {
  description = "Enable EFS encryption at rest"
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for the demo instance"
  type        = string
  default     = "t3.micro"
}

variable "create_demo_instance" {
  description = "Whether to create a demo EC2 instance for testing EFS mounting"
  type        = bool
  default     = true
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair for SSH access to the demo instance"
  type        = string
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the demo instance via SSH"
  type        = list(string)
  default     = []
}

variable "create_access_points" {
  description = "Whether to create EFS access points for different use cases"
  type        = bool
  default     = true
}

variable "access_point_configs" {
  description = "Configuration for EFS access points"
  type = map(object({
    path        = string
    uid         = number
    gid         = number
    permissions = string
  }))
  default = {
    app-data = {
      path        = "/app-data"
      uid         = 1000
      gid         = 1000
      permissions = "0755"
    }
    user-data = {
      path        = "/user-data"
      uid         = 2000
      gid         = 2000
      permissions = "0750"
    }
    logs = {
      path        = "/logs"
      uid         = 3000
      gid         = 3000
      permissions = "0755"
    }
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}