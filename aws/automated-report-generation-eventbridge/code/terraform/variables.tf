# Variables for automated report generation infrastructure

variable "project_name" {
  description = "Name of the project, used as a prefix for resource names"
  type        = string
  default     = "automated-reports"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# S3 Bucket Configuration
variable "data_bucket_prefix" {
  description = "Prefix for the S3 bucket that stores source data files"
  type        = string
  default     = "report-data"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.data_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "reports_bucket_prefix" {
  description = "Prefix for the S3 bucket that stores generated reports"
  type        = string
  default     = "report-output"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.reports_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# Lambda Function Configuration
variable "lambda_function_name" {
  description = "Name of the Lambda function for report generation"
  type        = string
  default     = "report-generator"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_name))
    error_message = "Lambda function name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_log_retention_days" {
  description = "Number of days to retain Lambda function logs in CloudWatch"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.lambda_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# EventBridge Scheduler Configuration
variable "schedule_name" {
  description = "Name of the EventBridge schedule for report generation"
  type        = string
  default     = "daily-reports"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.schedule_name))
    error_message = "Schedule name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "schedule_expression" {
  description = "Schedule expression in cron format for report generation"
  type        = string
  default     = "cron(0 9 * * ? *)"

  validation {
    condition     = can(regex("^(rate|cron)\\(.*\\)$", var.schedule_expression))
    error_message = "Schedule expression must be a valid rate or cron expression."
  }
}

variable "schedule_timezone" {
  description = "Timezone for the schedule expression"
  type        = string
  default     = "UTC"

  validation {
    condition     = can(regex("^[A-Za-z/_]+$", var.schedule_timezone))
    error_message = "Schedule timezone must be a valid timezone identifier."
  }
}

variable "schedule_state" {
  description = "State of the EventBridge schedule (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.schedule_state)
    error_message = "Schedule state must be either ENABLED or DISABLED."
  }
}

# SES Configuration
variable "verified_email" {
  description = "Email address for sending reports (must be verified in SES)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.verified_email))
    error_message = "Verified email must be a valid email address format."
  }
}

variable "create_ses_identity" {
  description = "Whether to create SES email identity resource (requires manual verification)"
  type        = bool
  default     = true
}

# Report Configuration
variable "report_schedule_description" {
  description = "Description for the report generation schedule"
  type        = string
  default     = "Daily business report generation schedule"
}

variable "enable_report_lifecycle" {
  description = "Whether to enable S3 lifecycle management for reports"
  type        = bool
  default     = true
}

variable "report_transition_ia_days" {
  description = "Number of days before transitioning reports to Infrequent Access storage"
  type        = number
  default     = 30

  validation {
    condition     = var.report_transition_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "report_transition_glacier_days" {
  description = "Number of days before transitioning reports to Glacier storage"
  type        = number
  default     = 90

  validation {
    condition     = var.report_transition_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

variable "report_expiration_days" {
  description = "Number of days before reports are automatically deleted"
  type        = number
  default     = 365

  validation {
    condition     = var.report_expiration_days >= 1
    error_message = "Report expiration must be at least 1 day."
  }
}

# Security Configuration
variable "enable_s3_encryption" {
  description = "Whether to enable server-side encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "enable_s3_versioning" {
  description = "Whether to enable versioning for S3 buckets"
  type        = bool
  default     = true
}

variable "block_public_access" {
  description = "Whether to block all public access to S3 buckets"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_cloudwatch_logs" {
  description = "Whether to enable CloudWatch logs for Lambda function"
  type        = bool
  default     = true
}

# Sample Data Configuration
variable "upload_sample_data" {
  description = "Whether to upload sample data files to the data bucket for testing"
  type        = bool
  default     = true
}

variable "sample_sales_data_key" {
  description = "S3 key for sample sales data file"
  type        = string
  default     = "sales/sample_sales.csv"
}

variable "sample_inventory_data_key" {
  description = "S3 key for sample inventory data file"
  type        = string
  default     = "inventory/sample_inventory.csv"
}

# Cost Optimization Configuration
variable "enable_cost_optimization" {
  description = "Whether to enable cost optimization features like lifecycle policies"
  type        = bool
  default     = true
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.additional_tags) <= 50
    error_message = "Cannot apply more than 50 additional tags."
  }
}