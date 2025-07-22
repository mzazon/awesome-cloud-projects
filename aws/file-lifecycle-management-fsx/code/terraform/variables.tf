# variables.tf
# Variable definitions for FSx Intelligent Tiering with Lambda lifecycle management

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "fsx-lifecycle-manager"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner of the resources (for tagging purposes)"
  type        = string
  default     = "platform-team"
}

# FSx Configuration Variables
variable "fsx_storage_capacity" {
  description = "FSx storage capacity in GiB (minimum 64, maximum 524,288)"
  type        = number
  default     = 64
  
  validation {
    condition     = var.fsx_storage_capacity >= 64 && var.fsx_storage_capacity <= 524288
    error_message = "FSx storage capacity must be between 64 and 524,288 GiB."
  }
}

variable "fsx_throughput_capacity" {
  description = "FSx throughput capacity in MBps (valid values: 160, 320, 640, 1280, 2560, 3840, 5120, 7680, 10240)"
  type        = number
  default     = 160
  
  validation {
    condition = contains([160, 320, 640, 1280, 2560, 3840, 5120, 7680, 10240], var.fsx_throughput_capacity)
    error_message = "FSx throughput capacity must be one of: 160, 320, 640, 1280, 2560, 3840, 5120, 7680, 10240 MBps."
  }
}

variable "fsx_deployment_type" {
  description = "FSx deployment type (must be SINGLE_AZ_2 for intelligent tiering)"
  type        = string
  default     = "SINGLE_AZ_2"
  
  validation {
    condition     = var.fsx_deployment_type == "SINGLE_AZ_2"
    error_message = "FSx deployment type must be SINGLE_AZ_2 for intelligent tiering support."
  }
}

variable "fsx_backup_retention_days" {
  description = "Number of days to retain automatic backups (0-90)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.fsx_backup_retention_days >= 0 && var.fsx_backup_retention_days <= 90
    error_message = "Backup retention days must be between 0 and 90."
  }
}

variable "fsx_backup_start_time" {
  description = "Daily automatic backup start time (HH:MM format)"
  type        = string
  default     = "05:00"
  
  validation {
    condition     = can(regex("^([0-1][0-9]|2[0-3]):[0-5][0-9]$", var.fsx_backup_start_time))
    error_message = "Backup start time must be in HH:MM format (24-hour)."
  }
}

# Networking Variables
variable "vpc_id" {
  description = "ID of the VPC where FSx will be deployed"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "ID of the subnet where FSx will be deployed"
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access FSx"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# Lambda Configuration Variables
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.12"
  
  validation {
    condition     = contains(["python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be python3.11 or python3.12."
  }
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB (128-10240)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds (1-900)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lifecycle_check_schedule" {
  description = "EventBridge schedule expression for lifecycle checks"
  type        = string
  default     = "rate(1 hour)"
}

variable "cost_report_schedule" {
  description = "EventBridge schedule expression for cost reporting"
  type        = string
  default     = "rate(24 hours)"
}

# Monitoring Variables
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid value."
  }
}

variable "storage_utilization_threshold" {
  description = "Storage utilization threshold for alerts (percentage)"
  type        = number
  default     = 85
  
  validation {
    condition     = var.storage_utilization_threshold >= 1 && var.storage_utilization_threshold <= 100
    error_message = "Storage utilization threshold must be between 1 and 100 percent."
  }
}

variable "cache_hit_ratio_threshold" {
  description = "Cache hit ratio threshold for alerts (percentage)"
  type        = number
  default     = 70
  
  validation {
    condition     = var.cache_hit_ratio_threshold >= 1 && var.cache_hit_ratio_threshold <= 100
    error_message = "Cache hit ratio threshold must be between 1 and 100 percent."
  }
}

# Notification Variables
variable "alert_email_addresses" {
  description = "List of email addresses to receive FSx alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All email addresses must be valid email format."
  }
}

# Security Variables
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for all applicable resources"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days (7-30)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# S3 Configuration Variables
variable "s3_reports_lifecycle_days" {
  description = "Number of days before transitioning S3 reports to IA storage"
  type        = number
  default     = 30
}

variable "s3_reports_glacier_days" {
  description = "Number of days before transitioning S3 reports to Glacier"
  type        = number
  default     = 90
}

variable "s3_reports_expiration_days" {
  description = "Number of days before expiring S3 reports"
  type        = number
  default     = 365
}

# Cost Optimization Variables
variable "enable_intelligent_tiering" {
  description = "Enable FSx Intelligent Tiering storage class"
  type        = bool
  default     = true
}

variable "lambda_architecture" {
  description = "Lambda architecture (x86_64 or arm64)"
  type        = string
  default     = "arm64"
  
  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Lambda architecture must be x86_64 or arm64."
  }
}