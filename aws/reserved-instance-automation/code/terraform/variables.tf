# Variables for Reserved Instance Management Automation
# This file defines all input variables for the Terraform configuration

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "ri-management"

  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be lowercase alphanumeric with hyphens, max 20 characters."
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

variable "notification_email" {
  description = "Email address for RI alerts and notifications"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "utilization_threshold" {
  description = "RI utilization percentage threshold for alerts (0-100)"
  type        = number
  default     = 80

  validation {
    condition     = var.utilization_threshold >= 0 && var.utilization_threshold <= 100
    error_message = "Utilization threshold must be between 0 and 100."
  }
}

variable "expiration_warning_days" {
  description = "Days before RI expiration to send warnings"
  type        = number
  default     = 90

  validation {
    condition     = var.expiration_warning_days >= 1 && var.expiration_warning_days <= 365
    error_message = "Expiration warning days must be between 1 and 365."
  }
}

variable "critical_expiration_days" {
  description = "Days before RI expiration to send critical alerts"
  type        = number
  default     = 30

  validation {
    condition     = var.critical_expiration_days >= 1 && var.critical_expiration_days <= 365
    error_message = "Critical expiration days must be between 1 and 365."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 and 3008 MB."
  }
}

variable "enable_cost_explorer_api" {
  description = "Enable Cost Explorer API access (may incur charges)"
  type        = bool
  default     = true
}

variable "daily_analysis_schedule" {
  description = "Cron expression for daily RI utilization analysis"
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "weekly_recommendations_schedule" {
  description = "Cron expression for weekly RI recommendations"
  type        = string
  default     = "cron(0 9 ? * MON *)"
}

variable "weekly_monitoring_schedule" {
  description = "Cron expression for weekly RI monitoring"
  type        = string
  default     = "cron(0 10 ? * MON *)"
}

variable "s3_bucket_versioning" {
  description = "Enable S3 bucket versioning for RI reports"
  type        = bool
  default     = true
}

variable "s3_bucket_lifecycle_days" {
  description = "Days after which to transition S3 objects to IA storage"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_bucket_lifecycle_days >= 1
    error_message = "S3 lifecycle days must be at least 1."
  }
}

variable "dynamodb_point_in_time_recovery" {
  description = "Enable DynamoDB point-in-time recovery"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda functions (optional)"
  type        = number
  default     = null

  validation {
    condition = var.lambda_reserved_concurrency == null || (var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000)
    error_message = "Reserved concurrency must be between 0 and 1000 or null."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}