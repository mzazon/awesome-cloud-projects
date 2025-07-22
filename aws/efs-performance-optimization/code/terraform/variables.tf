# General Configuration
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "efs-performance"
}

# VPC Configuration
variable "vpc_id" {
  description = "VPC ID where EFS will be deployed. If not provided, will use default VPC"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets. If not provided, will use subnets from default VPC"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones to use for mount targets. Used when subnet_ids is empty"
  type        = list(string)
  default     = []
}

# EFS Configuration
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
  default     = "provisioned"
  
  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be 'bursting', 'provisioned', or 'elastic'."
  }
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s (only used when throughput_mode is 'provisioned')"
  type        = number
  default     = 100
  
  validation {
    condition     = var.efs_provisioned_throughput >= 1 && var.efs_provisioned_throughput <= 4000
    error_message = "Provisioned throughput must be between 1 and 4000 MiB/s."
  }
}

variable "efs_encrypted" {
  description = "Enable encryption at rest for EFS"
  type        = bool
  default     = true
}

variable "efs_backup_enabled" {
  description = "Enable automatic backups for EFS"
  type        = bool
  default     = true
}

variable "efs_lifecycle_policy" {
  description = "EFS lifecycle policy for transitioning files to IA storage class"
  type        = string
  default     = "AFTER_30_DAYS"
  
  validation {
    condition = contains([
      "AFTER_1_DAY", "AFTER_7_DAYS", "AFTER_14_DAYS", 
      "AFTER_30_DAYS", "AFTER_60_DAYS", "AFTER_90_DAYS"
    ], var.efs_lifecycle_policy)
    error_message = "Lifecycle policy must be one of: AFTER_1_DAY, AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS."
  }
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access EFS"
  type        = list(string)
  default     = []
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to allow access to EFS"
  type        = list(string)
  default     = []
}

# CloudWatch Monitoring Configuration
variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for EFS monitoring"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for EFS monitoring"
  type        = bool
  default     = true
}

variable "alarm_throughput_threshold" {
  description = "Threshold for throughput utilization alarm (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.alarm_throughput_threshold > 0 && var.alarm_throughput_threshold <= 100
    error_message = "Alarm throughput threshold must be between 1 and 100."
  }
}

variable "alarm_connections_threshold" {
  description = "Threshold for client connections alarm"
  type        = number
  default     = 500
  
  validation {
    condition     = var.alarm_connections_threshold > 0
    error_message = "Alarm connections threshold must be greater than 0."
  }
}

variable "alarm_latency_threshold" {
  description = "Threshold for IO latency alarm (milliseconds)"
  type        = number
  default     = 50
  
  validation {
    condition     = var.alarm_latency_threshold > 0
    error_message = "Alarm latency threshold must be greater than 0."
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications. If not provided, alarms will be created without notifications"
  type        = string
  default     = null
}

# EC2 Test Instance Configuration
variable "create_test_instance" {
  description = "Create EC2 test instance for EFS validation"
  type        = bool
  default     = false
}

variable "test_instance_type" {
  description = "EC2 instance type for test instance"
  type        = string
  default     = "t3.medium"
}

variable "test_instance_key_name" {
  description = "EC2 key pair name for test instance (required if create_test_instance is true)"
  type        = string
  default     = null
}

# Resource Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}