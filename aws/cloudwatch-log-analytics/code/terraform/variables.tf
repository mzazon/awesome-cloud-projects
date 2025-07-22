# Variables for Log Analytics Solution with CloudWatch Logs Insights
# This file defines all configurable parameters for the infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z]+$", var.environment))
    error_message = "Environment must be lowercase letters only."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "log-analytics"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch retention periods."
  }
}

variable "notification_email" {
  description = "Email address for log analytics alerts"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 10 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 10 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "analysis_schedule" {
  description = "Schedule expression for automated log analysis (CloudWatch Events format)"
  type        = string
  default     = "rate(5 minutes)"
  
  validation {
    condition     = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", var.analysis_schedule))
    error_message = "Schedule must be in CloudWatch Events format: rate(5 minutes) or cron(0 12 * * ? *)."
  }
}

variable "error_threshold" {
  description = "Number of errors that trigger an alert"
  type        = number
  default     = 1
  
  validation {
    condition     = var.error_threshold >= 0
    error_message = "Error threshold must be a non-negative number."
  }
}

variable "analysis_window_hours" {
  description = "Time window in hours for log analysis"
  type        = number
  default     = 1
  
  validation {
    condition     = var.analysis_window_hours >= 1 && var.analysis_window_hours <= 24
    error_message = "Analysis window must be between 1 and 24 hours."
  }
}

variable "enable_sample_data" {
  description = "Whether to create sample log data for testing"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}