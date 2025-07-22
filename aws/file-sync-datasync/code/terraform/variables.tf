# -----------------------------------------------------------------------------
# General Configuration Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "AWS region for resource deployment"
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  type        = string
  description = "Environment name for resource tagging"
  default     = "dev"

  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  type        = string
  description = "Project name for resource naming and tagging"
  default     = "datasync-efs-sync"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# VPC Configuration Variables
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the private subnet"
  default     = "10.0.1.0/24"

  validation {
    condition = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "Private subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone" {
  type        = string
  description = "Availability zone for subnet placement (optional - will use first AZ if not specified)"
  default     = ""
}

# -----------------------------------------------------------------------------
# EFS Configuration Variables
# -----------------------------------------------------------------------------

variable "efs_performance_mode" {
  type        = string
  description = "Performance mode for EFS file system"
  default     = "generalPurpose"

  validation {
    condition = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "EFS performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "efs_throughput_mode" {
  type        = string
  description = "Throughput mode for EFS file system"
  default     = "provisioned"

  validation {
    condition = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput" {
  type        = number
  description = "Provisioned throughput in MiB/s (only used when throughput_mode is 'provisioned')"
  default     = 100

  validation {
    condition = var.efs_provisioned_throughput >= 1 && var.efs_provisioned_throughput <= 4000
    error_message = "EFS provisioned throughput must be between 1 and 4000 MiB/s."
  }
}

variable "efs_encrypted" {
  type        = bool
  description = "Enable encryption at rest for EFS file system"
  default     = true
}

variable "efs_transition_to_ia" {
  type        = string
  description = "Lifecycle policy for transitioning files to Infrequent Access storage class"
  default     = "AFTER_30_DAYS"

  validation {
    condition = contains([
      "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS", 
      "AFTER_60_DAYS", "AFTER_90_DAYS", ""
    ], var.efs_transition_to_ia)
    error_message = "EFS IA transition must be one of: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, or empty string to disable."
  }
}

# -----------------------------------------------------------------------------
# S3 Configuration Variables
# -----------------------------------------------------------------------------

variable "create_source_bucket" {
  type        = bool
  description = "Create a source S3 bucket for testing purposes"
  default     = true
}

variable "source_bucket_name" {
  type        = string
  description = "Name of the source S3 bucket (if create_source_bucket is false, this should be an existing bucket)"
  default     = ""
}

variable "enable_s3_versioning" {
  type        = bool
  description = "Enable versioning on the source S3 bucket"
  default     = false
}

variable "s3_storage_class" {
  type        = string
  description = "Default storage class for S3 objects"
  default     = "STANDARD"

  validation {
    condition = contains([
      "STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", 
      "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE"
    ], var.s3_storage_class)
    error_message = "S3 storage class must be a valid AWS S3 storage class."
  }
}

# -----------------------------------------------------------------------------
# DataSync Configuration Variables
# -----------------------------------------------------------------------------

variable "datasync_task_name" {
  type        = string
  description = "Name for the DataSync task"
  default     = ""
}

variable "datasync_verify_mode" {
  type        = string
  description = "Data verification mode for DataSync"
  default     = "POINT_IN_TIME_CONSISTENT"

  validation {
    condition = contains([
      "POINT_IN_TIME_CONSISTENT", "ONLY_FILES_TRANSFERRED", "NONE"
    ], var.datasync_verify_mode)
    error_message = "DataSync verify mode must be one of: POINT_IN_TIME_CONSISTENT, ONLY_FILES_TRANSFERRED, NONE."
  }
}

variable "datasync_overwrite_mode" {
  type        = string
  description = "Overwrite mode for DataSync when files exist at destination"
  default     = "ALWAYS"

  validation {
    condition = contains(["ALWAYS", "NEVER"], var.datasync_overwrite_mode)
    error_message = "DataSync overwrite mode must be either 'ALWAYS' or 'NEVER'."
  }
}

variable "datasync_preserve_deleted_files" {
  type        = string
  description = "Whether to preserve files that are deleted from source"
  default     = "PRESERVE"

  validation {
    condition = contains(["PRESERVE", "REMOVE"], var.datasync_preserve_deleted_files)
    error_message = "DataSync preserve deleted files must be either 'PRESERVE' or 'REMOVE'."
  }
}

variable "datasync_log_level" {
  type        = string
  description = "Log level for DataSync operations"
  default     = "TRANSFER"

  validation {
    condition = contains(["OFF", "BASIC", "TRANSFER"], var.datasync_log_level)
    error_message = "DataSync log level must be one of: OFF, BASIC, TRANSFER."
  }
}

variable "datasync_bandwidth_limit" {
  type        = number
  description = "Bandwidth limit in bytes per second (-1 for unlimited)"
  default     = -1

  validation {
    condition = var.datasync_bandwidth_limit >= -1
    error_message = "DataSync bandwidth limit must be -1 (unlimited) or a positive number."
  }
}

# -----------------------------------------------------------------------------
# Monitoring and Notification Variables
# -----------------------------------------------------------------------------

variable "enable_cloudwatch_logs" {
  type        = bool
  description = "Enable CloudWatch Logs for DataSync"
  default     = true
}

variable "cloudwatch_log_retention_days" {
  type        = number
  description = "Number of days to retain CloudWatch logs"
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

variable "enable_sns_notifications" {
  type        = bool
  description = "Enable SNS notifications for DataSync task completion"
  default     = false
}

variable "notification_email" {
  type        = string
  description = "Email address for SNS notifications (required if enable_sns_notifications is true)"
  default     = ""

  validation {
    condition = var.enable_sns_notifications == false || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "A valid email address is required when SNS notifications are enabled."
  }
}

# -----------------------------------------------------------------------------
# Sample Data Configuration Variables
# -----------------------------------------------------------------------------

variable "create_sample_data" {
  type        = bool
  description = "Create sample data in the source S3 bucket for testing"
  default     = true
}

variable "sample_data_files" {
  type = list(object({
    key     = string
    content = string
  }))
  description = "List of sample files to create in the source bucket"
  default = [
    {
      key     = "sample1.txt"
      content = "Sample file 1 content for DataSync testing"
    },
    {
      key     = "sample2.txt"
      content = "Sample file 2 content with different data"
    },
    {
      key     = "test-folder/nested.txt"
      content = "Nested file content to test directory synchronization"
    },
    {
      key     = "documents/readme.md"
      content = "# DataSync Test Files\n\nThis directory contains test files for DataSync synchronization testing."
    }
  ]
}