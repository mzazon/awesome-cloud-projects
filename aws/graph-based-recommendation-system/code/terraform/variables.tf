# Variables for Neptune Graph Database Recommendation Engine
# This file defines all input variables for the Terraform configuration

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-west-2)."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "neptune-recommendations"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

# VPC Configuration Variables
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
  description = "List of availability zones for multi-AZ deployment"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (Neptune)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for Neptune Multi-AZ deployment."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (EC2 client)"
  type        = list(string)
  default     = ["10.0.10.0/24"]
}

# Neptune Cluster Configuration
variable "neptune_cluster_identifier" {
  description = "Identifier for the Neptune cluster"
  type        = string
  default     = ""
}

variable "neptune_engine_version" {
  description = "Neptune engine version"
  type        = string
  default     = "1.3.2.0"
}

variable "neptune_instance_class" {
  description = "Instance class for Neptune instances"
  type        = string
  default     = "db.r5.large"

  validation {
    condition = contains([
      "db.r5.large", "db.r5.xlarge", "db.r5.2xlarge", "db.r5.4xlarge",
      "db.r6g.large", "db.r6g.xlarge", "db.r6g.2xlarge", "db.r6g.4xlarge",
      "db.t3.medium", "db.t4g.medium"
    ], var.neptune_instance_class)
    error_message = "Neptune instance class must be a valid Neptune-supported instance type."
  }
}

variable "neptune_replica_count" {
  description = "Number of Neptune read replicas to create"
  type        = number
  default     = 2

  validation {
    condition     = var.neptune_replica_count >= 0 && var.neptune_replica_count <= 15
    error_message = "Neptune replica count must be between 0 and 15."
  }
}

variable "neptune_backup_retention_period" {
  description = "Number of days to retain Neptune backups"
  type        = number
  default     = 7

  validation {
    condition     = var.neptune_backup_retention_period >= 1 && var.neptune_backup_retention_period <= 35
    error_message = "Neptune backup retention period must be between 1 and 35 days."
  }
}

variable "neptune_backup_window" {
  description = "Preferred backup window for Neptune cluster"
  type        = string
  default     = "03:00-04:00"

  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]-([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.neptune_backup_window))
    error_message = "Neptune backup window must be in format HH:MM-HH:MM (24-hour format)."
  }
}

variable "neptune_maintenance_window" {
  description = "Preferred maintenance window for Neptune cluster"
  type        = string
  default     = "sun:04:00-sun:05:00"

  validation {
    condition = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.neptune_maintenance_window))
    error_message = "Neptune maintenance window must be in format ddd:HH:MM-ddd:HH:MM."
  }
}

variable "neptune_storage_encrypted" {
  description = "Whether to encrypt Neptune storage"
  type        = bool
  default     = true
}

variable "neptune_kms_key_id" {
  description = "KMS key ID for Neptune encryption (leave empty for default)"
  type        = string
  default     = ""
}

# EC2 Client Instance Configuration
variable "ec2_instance_type" {
  description = "Instance type for the EC2 client instance"
  type        = string
  default     = "t3.medium"

  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3a.micro", "t3a.small", "t3a.medium", "t3a.large",
      "m5.large", "m5.xlarge", "c5.large", "c5.xlarge"
    ], var.ec2_instance_type)
    error_message = "EC2 instance type must be a valid instance type."
  }
}

variable "ec2_key_pair_name" {
  description = "Name of the EC2 key pair (will be created if it doesn't exist)"
  type        = string
  default     = ""
}

variable "ec2_associate_public_ip" {
  description = "Whether to associate a public IP with the EC2 instance"
  type        = bool
  default     = true
}

variable "ec2_user_data_script" {
  description = "User data script for EC2 instance initialization"
  type        = string
  default     = ""
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for sample data (will be generated if empty)"
  type        = string
  default     = ""
}

variable "s3_force_destroy" {
  description = "Whether to force destroy S3 bucket with objects"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access EC2 instance via SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All allowed CIDR blocks must be valid IPv4 CIDR notation."
  }
}

variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection for Neptune cluster"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_logs" {
  description = "Whether to enable CloudWatch logs for Neptune"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

# Cost Optimization
variable "enable_auto_minor_version_upgrade" {
  description = "Whether to enable automatic minor version upgrades for Neptune"
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Whether to apply Neptune changes immediately"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}