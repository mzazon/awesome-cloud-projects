# AWS Region configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Environment configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

# Project name for resource naming
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "distributed-efs"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# VPC configuration
variable "vpc_id" {
  description = "VPC ID where resources will be created. If not provided, uses default VPC"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets. If not provided, uses default VPC subnets"
  type        = list(string)
  default     = []
}

# EFS configuration
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
  description = "EFS throughput mode (bursting, provisioned, or elastic)"
  type        = string
  default     = "elastic"
  
  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be 'bursting', 'provisioned', or 'elastic'."
  }
}

variable "provisioned_throughput_in_mibps" {
  description = "Provisioned throughput in MiB/s (only used if throughput_mode is provisioned)"
  type        = number
  default     = null
}

variable "enable_encryption" {
  description = "Enable encryption at rest for EFS"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for EFS encryption. If not provided, uses AWS managed key"
  type        = string
  default     = null
}

# Lifecycle policy configuration
variable "transition_to_ia" {
  description = "Transition to Infrequent Access storage class (AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS)"
  type        = string
  default     = "AFTER_30_DAYS"
  
  validation {
    condition = contains([
      "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS", 
      "AFTER_60_DAYS", "AFTER_90_DAYS"
    ], var.transition_to_ia)
    error_message = "Transition to IA must be one of: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS."
  }
}

variable "transition_to_primary_storage_class" {
  description = "Transition back to primary storage class (AFTER_1_ACCESS)"
  type        = string
  default     = "AFTER_1_ACCESS"
  
  validation {
    condition     = contains(["AFTER_1_ACCESS"], var.transition_to_primary_storage_class)
    error_message = "Transition to primary storage class must be 'AFTER_1_ACCESS'."
  }
}

# EC2 configuration
variable "create_ec2_instances" {
  description = "Whether to create EC2 instances for testing EFS"
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access. If not provided, instances will be created without SSH access"
  type        = string
  default     = null
}

variable "enable_ssh_access" {
  description = "Enable SSH access to EC2 instances (port 22)"
  type        = bool
  default     = true
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Monitoring configuration
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring with dashboard and log groups"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid value."
  }
}

# Backup configuration
variable "enable_backup" {
  description = "Enable AWS Backup for EFS"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Backup schedule in cron format"
  type        = string
  default     = "cron(0 2 ? * * *)"
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}

variable "backup_start_window_minutes" {
  description = "Backup start window in minutes"
  type        = number
  default     = 60
  
  validation {
    condition     = var.backup_start_window_minutes >= 60
    error_message = "Backup start window must be at least 60 minutes."
  }
}

# Access point configuration
variable "access_points" {
  description = "List of access points to create"
  type = list(object({
    name        = string
    path        = string
    owner_uid   = number
    owner_gid   = number
    permissions = string
    posix_uid   = number
    posix_gid   = number
  }))
  default = [
    {
      name        = "web-content"
      path        = "/web-content"
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
      posix_uid   = 1000
      posix_gid   = 1000
    },
    {
      name        = "shared-data"
      path        = "/shared-data"
      owner_uid   = 1001
      owner_gid   = 1001
      permissions = "750"
      posix_uid   = 1001
      posix_gid   = 1001
    }
  ]
}

# Security configuration
variable "enable_file_system_policy" {
  description = "Enable file system policy for access control"
  type        = bool
  default     = true
}

variable "enforce_secure_transport" {
  description = "Enforce secure transport (TLS) for file system access"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}