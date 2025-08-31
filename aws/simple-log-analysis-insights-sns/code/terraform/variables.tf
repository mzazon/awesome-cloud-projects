# Variables for the Simple Log Analysis with CloudWatch Insights and SNS solution
# These variables allow customization of the infrastructure deployment

variable "project_name" {
  description = "Name of the project, used as a prefix for resource naming"
  type        = string
  default     = "log-analysis"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
}

variable "log_group_name" {
  description = "Name of the CloudWatch Log Group to monitor"
  type        = string
  default     = "/aws/lambda/demo-app"
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "notification_email" {
  description = "Email address to receive SNS notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "analysis_schedule" {
  description = "EventBridge schedule expression for log analysis (e.g., 'rate(5 minutes)')"
  type        = string
  default     = "rate(5 minutes)"
  
  validation {
    condition     = can(regex("^(rate\\(\\d+\\s+(minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.analysis_schedule))
    error_message = "Schedule must be a valid EventBridge expression like 'rate(5 minutes)' or a cron expression."
  }
}

variable "error_patterns" {
  description = "List of error patterns to search for in log messages"
  type        = list(string)
  default     = ["ERROR", "CRITICAL", "FATAL"]
}

variable "query_time_range_minutes" {
  description = "Time range in minutes to query for log analysis"
  type        = number
  default     = 10
  
  validation {
    condition     = var.query_time_range_minutes >= 1 && var.query_time_range_minutes <= 1440
    error_message = "Query time range must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "max_errors_to_display" {
  description = "Maximum number of errors to display in SNS notifications"
  type        = number
  default     = 5
  
  validation {
    condition     = var.max_errors_to_display >= 1 && var.max_errors_to_display <= 20
    error_message = "Max errors to display must be between 1 and 20."
  }
}

variable "enable_sns_subscription" {
  description = "Whether to create an email subscription to the SNS topic"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}