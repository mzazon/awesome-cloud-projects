# General Configuration
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
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "cost_center" {
  description = "Cost center for resource billing and tracking"
  type        = string
  default     = "research"
}

variable "owner" {
  description = "Owner or team responsible for the infrastructure"
  type        = string
  default     = "hpc-team"
}

# Naming and Identification
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "hpc-batch"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# Networking Configuration
variable "use_default_vpc" {
  description = "Whether to use the default VPC for deployment"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID to deploy resources in (if not using default VPC)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for Batch compute environment (if not using default VPC)"
  type        = list(string)
  default     = []
}

# Batch Compute Environment Configuration
variable "max_vcpus" {
  description = "Maximum number of vCPUs for the Batch compute environment"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.max_vcpus >= 0 && var.max_vcpus <= 10000
    error_message = "Max vCPUs must be between 0 and 10000."
  }
}

variable "desired_vcpus" {
  description = "Desired number of vCPUs for the Batch compute environment"
  type        = number
  default     = 0
  
  validation {
    condition     = var.desired_vcpus >= 0
    error_message = "Desired vCPUs must be non-negative."
  }
}

variable "instance_types" {
  description = "List of EC2 instance types for the Batch compute environment"
  type        = list(string)
  default     = ["c5.large", "c5.xlarge", "c5.2xlarge", "c4.large", "c4.xlarge", "m5.large", "m5.xlarge"]
  
  validation {
    condition     = length(var.instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

variable "spot_bid_percentage" {
  description = "Percentage of On-Demand price to bid for Spot instances"
  type        = number
  default     = 80
  
  validation {
    condition     = var.spot_bid_percentage >= 10 && var.spot_bid_percentage <= 100
    error_message = "Spot bid percentage must be between 10 and 100."
  }
}

variable "allocation_strategy" {
  description = "Allocation strategy for the Batch compute environment"
  type        = string
  default     = "SPOT_CAPACITY_OPTIMIZED"
  
  validation {
    condition = contains([
      "BEST_FIT",
      "BEST_FIT_PROGRESSIVE",
      "SPOT_CAPACITY_OPTIMIZED"
    ], var.allocation_strategy)
    error_message = "Allocation strategy must be one of: BEST_FIT, BEST_FIT_PROGRESSIVE, SPOT_CAPACITY_OPTIMIZED."
  }
}

# Job Configuration
variable "job_timeout_seconds" {
  description = "Timeout for Batch jobs in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.job_timeout_seconds >= 60 && var.job_timeout_seconds <= 86400
    error_message = "Job timeout must be between 60 seconds (1 minute) and 86400 seconds (24 hours)."
  }
}

variable "job_retry_attempts" {
  description = "Number of retry attempts for failed Batch jobs"
  type        = number
  default     = 3
  
  validation {
    condition     = var.job_retry_attempts >= 1 && var.job_retry_attempts <= 10
    error_message = "Job retry attempts must be between 1 and 10."
  }
}

variable "job_vcpus" {
  description = "Number of vCPUs for each Batch job"
  type        = number
  default     = 2
  
  validation {
    condition     = var.job_vcpus >= 1 && var.job_vcpus <= 256
    error_message = "Job vCPUs must be between 1 and 256."
  }
}

variable "job_memory_mb" {
  description = "Memory allocation for each Batch job in MB"
  type        = number
  default     = 4096
  
  validation {
    condition     = var.job_memory_mb >= 512 && var.job_memory_mb <= 30720
    error_message = "Job memory must be between 512 MB and 30720 MB (30 GB)."
  }
}

variable "container_image" {
  description = "Container image for Batch jobs"
  type        = string
  default     = "busybox"
}

# EFS Configuration
variable "enable_efs" {
  description = "Whether to create and mount EFS for shared storage"
  type        = bool
  default     = true
}

variable "efs_performance_mode" {
  description = "Performance mode for EFS file system"
  type        = string
  default     = "generalPurpose"
  
  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "EFS performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "efs_throughput_mode" {
  description = "Throughput mode for EFS file system"
  type        = string
  default     = "provisioned"
  
  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput_mibps" {
  description = "Provisioned throughput for EFS in MiB/s (only used when throughput_mode is 'provisioned')"
  type        = number
  default     = 100
  
  validation {
    condition     = var.efs_provisioned_throughput_mibps >= 1 && var.efs_provisioned_throughput_mibps <= 1024
    error_message = "EFS provisioned throughput must be between 1 and 1024 MiB/s."
  }
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket (will be prefixed with project name and random suffix)"
  type        = string
  default     = "data"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.s3_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "s3_bucket_versioning" {
  description = "Whether to enable versioning on the S3 bucket"
  type        = bool
  default     = false
}

variable "s3_lifecycle_enabled" {
  description = "Whether to enable lifecycle policies on the S3 bucket"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be one of the valid values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}

variable "enable_detailed_monitoring" {
  description = "Whether to enable detailed CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "failed_jobs_alarm_threshold" {
  description = "Threshold for failed jobs CloudWatch alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.failed_jobs_alarm_threshold >= 1 && var.failed_jobs_alarm_threshold <= 100
    error_message = "Failed jobs alarm threshold must be between 1 and 100."
  }
}

# Security Configuration
variable "enable_encryption" {
  description = "Whether to enable encryption for S3 and EFS"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}