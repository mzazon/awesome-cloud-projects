# AWS Region Configuration
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1, eu-west-1)."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for cost anomaly notifications"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

# Cost Anomaly Detection Thresholds
variable "daily_summary_threshold" {
  description = "Minimum anomaly impact (USD) for daily summary alerts"
  type        = number
  default     = 100

  validation {
    condition     = var.daily_summary_threshold >= 0
    error_message = "Daily summary threshold must be a positive number."
  }
}

variable "individual_alert_threshold" {
  description = "Minimum anomaly impact (USD) for individual alerts"
  type        = number
  default     = 50

  validation {
    condition     = var.individual_alert_threshold >= 0
    error_message = "Individual alert threshold must be a positive number."
  }
}

# Tag-based Monitor Configuration
variable "environment_tags" {
  description = "List of environment tag values to monitor for cost anomalies"
  type        = list(string)
  default     = ["Production", "Staging"]

  validation {
    condition     = length(var.environment_tags) > 0
    error_message = "At least one environment tag must be specified."
  }
}

# Lambda Function Configuration
variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "cost-anomaly"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.resource_prefix))
    error_message = "Resource prefix must be lowercase alphanumeric with hyphens, max 20 characters."
  }
}

# CloudWatch Dashboard Configuration
variable "create_dashboard" {
  description = "Whether to create a CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

# Cost Allocation Tags
variable "cost_allocation_tags" {
  description = "Additional tags for cost allocation and tracking"
  type        = map(string)
  default     = {}
}