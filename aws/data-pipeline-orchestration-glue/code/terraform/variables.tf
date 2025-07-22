# variables.tf - Input variables for AWS Glue Workflows infrastructure
# This file defines all configurable parameters for the data pipeline orchestration solution

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "data-pipeline"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "workflow_schedule" {
  description = "Cron expression for workflow scheduling (UTC)"
  type        = string
  default     = "cron(0 2 * * ? *)"
  
  validation {
    condition = can(regex("^cron\\(.*\\)$", var.workflow_schedule))
    error_message = "Workflow schedule must be a valid cron expression format."
  }
}

variable "glue_job_timeout" {
  description = "Timeout for Glue jobs in minutes"
  type        = number
  default     = 60
  
  validation {
    condition = var.glue_job_timeout >= 1 && var.glue_job_timeout <= 2880
    error_message = "Glue job timeout must be between 1 and 2880 minutes."
  }
}

variable "glue_job_max_retries" {
  description = "Maximum number of retries for Glue jobs"
  type        = number
  default     = 1
  
  validation {
    condition = var.glue_job_max_retries >= 0 && var.glue_job_max_retries <= 10
    error_message = "Glue job max retries must be between 0 and 10."
  }
}

variable "glue_version" {
  description = "AWS Glue version to use for jobs"
  type        = string
  default     = "4.0"
  
  validation {
    condition = contains(["2.0", "3.0", "4.0"], var.glue_version)
    error_message = "Glue version must be one of: 2.0, 3.0, 4.0."
  }
}

variable "max_concurrent_runs" {
  description = "Maximum number of concurrent workflow runs"
  type        = number
  default     = 1
  
  validation {
    condition = var.max_concurrent_runs >= 1 && var.max_concurrent_runs <= 100
    error_message = "Max concurrent runs must be between 1 and 100."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Glue jobs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention period."
  }
}

variable "s3_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_bucket_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "force_destroy_buckets" {
  description = "Allow Terraform to destroy S3 buckets with content (use with caution)"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "crawler_schedule" {
  description = "Schedule for running crawlers independently (optional)"
  type        = string
  default     = null
}

variable "database_description" {
  description = "Description for the Glue database"
  type        = string
  default     = "Database for workflow data catalog metadata"
}

variable "enable_workflow_notifications" {
  description = "Enable SNS notifications for workflow events"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for workflow notifications (required if enable_workflow_notifications is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.enable_workflow_notifications == false || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "A valid email address is required when notifications are enabled."
  }
}