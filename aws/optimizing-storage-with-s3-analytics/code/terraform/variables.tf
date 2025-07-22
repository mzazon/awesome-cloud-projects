# Variables for S3 Inventory and Storage Analytics Reporting

variable "aws_region" {
  description = "AWS region where resources will be created"
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
    condition = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "storage-analytics"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "source_bucket_name" {
  description = "Name of the S3 source bucket to analyze (leave empty to create new bucket)"
  type        = string
  default     = ""
}

variable "inventory_frequency" {
  description = "Frequency of S3 inventory reports"
  type        = string
  default     = "Daily"

  validation {
    condition = contains(["Daily", "Weekly"], var.inventory_frequency)
    error_message = "Inventory frequency must be either 'Daily' or 'Weekly'."
  }
}

variable "inventory_included_object_versions" {
  description = "Object versions to include in inventory"
  type        = string
  default     = "Current"

  validation {
    condition = contains(["All", "Current"], var.inventory_included_object_versions)
    error_message = "Included object versions must be either 'All' or 'Current'."
  }
}

variable "storage_analytics_prefix" {
  description = "Prefix filter for storage class analysis"
  type        = string
  default     = "data/"
}

variable "athena_database_name" {
  description = "Name of the Athena database for inventory queries"
  type        = string
  default     = "s3_inventory_db"

  validation {
    condition = can(regex("^[a-z0-9_]+$", var.athena_database_name))
    error_message = "Athena database name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "athena_table_name" {
  description = "Name of the Athena table for inventory data"
  type        = string
  default     = "inventory_table"

  validation {
    condition = can(regex("^[a-z0-9_]+$", var.athena_table_name))
    error_message = "Athena table name must contain only lowercase letters, numbers, and underscores."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"

  validation {
    condition = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "reporting_schedule" {
  description = "Schedule expression for automated reporting (EventBridge format)"
  type        = string
  default     = "rate(1 day)"

  validation {
    condition = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", var.reporting_schedule))
    error_message = "Schedule must be in EventBridge format (rate() or cron())."
  }
}

variable "create_sample_data" {
  description = "Whether to create sample data in the source bucket for testing"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Number of days to retain inventory and analytics reports"
  type        = number
  default     = 90

  validation {
    condition = var.retention_days >= 1 && var.retention_days <= 3653
    error_message = "Retention days must be between 1 and 3653 (10 years)."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_automated_reporting" {
  description = "Whether to enable automated reporting with Lambda and EventBridge"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300

  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256

  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}