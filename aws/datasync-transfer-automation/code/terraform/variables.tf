# AWS Region
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Environment
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Project Name
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "datasync-automation"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Source Bucket Configuration
variable "source_bucket_name" {
  description = "Name for the source S3 bucket. If empty, a unique name will be generated."
  type        = string
  default     = ""
}

# Destination Bucket Configuration
variable "destination_bucket_name" {
  description = "Name for the destination S3 bucket. If empty, a unique name will be generated."
  type        = string
  default     = ""
}

# S3 Bucket Versioning
variable "enable_bucket_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

# S3 Bucket Encryption
variable "enable_bucket_encryption" {
  description = "Enable server-side encryption on S3 buckets"
  type        = bool
  default     = true
}

# DataSync Task Configuration
variable "datasync_task_name" {
  description = "Name for the DataSync task"
  type        = string
  default     = "datasync-s3-to-s3-task"
}

# DataSync Options
variable "datasync_verify_mode" {
  description = "Verification mode for DataSync task"
  type        = string
  default     = "POINT_IN_TIME_CONSISTENT"
  
  validation {
    condition = contains([
      "POINT_IN_TIME_CONSISTENT",
      "ONLY_FILES_TRANSFERRED",
      "NONE"
    ], var.datasync_verify_mode)
    error_message = "Verify mode must be POINT_IN_TIME_CONSISTENT, ONLY_FILES_TRANSFERRED, or NONE."
  }
}

variable "datasync_overwrite_mode" {
  description = "Overwrite mode for DataSync task"
  type        = string
  default     = "ALWAYS"
  
  validation {
    condition = contains([
      "ALWAYS",
      "NEVER"
    ], var.datasync_overwrite_mode)
    error_message = "Overwrite mode must be ALWAYS or NEVER."
  }
}

variable "datasync_transfer_mode" {
  description = "Transfer mode for DataSync task"
  type        = string
  default     = "CHANGED"
  
  validation {
    condition = contains([
      "CHANGED",
      "ALL"
    ], var.datasync_transfer_mode)
    error_message = "Transfer mode must be CHANGED or ALL."
  }
}

variable "datasync_log_level" {
  description = "Log level for DataSync task"
  type        = string
  default     = "TRANSFER"
  
  validation {
    condition = contains([
      "OFF",
      "BASIC",
      "TRANSFER"
    ], var.datasync_log_level)
    error_message = "Log level must be OFF, BASIC, or TRANSFER."
  }
}

# Bandwidth Throttling
variable "datasync_bandwidth_throttle" {
  description = "Bandwidth throttle for DataSync in bytes per second. -1 for unlimited."
  type        = number
  default     = -1
  
  validation {
    condition     = var.datasync_bandwidth_throttle == -1 || var.datasync_bandwidth_throttle > 0
    error_message = "Bandwidth throttle must be -1 (unlimited) or a positive number."
  }
}

# CloudWatch Retention
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

# Scheduled Execution
variable "enable_scheduled_execution" {
  description = "Enable scheduled execution of DataSync task"
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for automated execution"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition     = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", var.schedule_expression))
    error_message = "Schedule expression must be a valid rate() or cron() expression."
  }
}

# Task Reporting
variable "enable_task_reporting" {
  description = "Enable task reporting for DataSync"
  type        = bool
  default     = true
}

variable "task_report_level" {
  description = "Task report level"
  type        = string
  default     = "ERRORS_ONLY"
  
  validation {
    condition = contains([
      "ERRORS_ONLY",
      "SUCCESSES_AND_ERRORS"
    ], var.task_report_level)
    error_message = "Task report level must be ERRORS_ONLY or SUCCESSES_AND_ERRORS."
  }
}

# CloudWatch Dashboard
variable "enable_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

# Sample Data
variable "create_sample_data" {
  description = "Create sample data in source bucket for testing"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}