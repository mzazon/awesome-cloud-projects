# Variables for Basic Log Monitoring Infrastructure

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^(dev|test|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  type        = string
  default     = "/aws/application/monitoring-demo"
  
  validation {
    condition = can(regex("^[\\w.-_/]+$", var.log_group_name))
    error_message = "Log group name must contain only alphanumeric characters, hyphens, underscores, periods, and forward slashes."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in CloudWatch"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2557, 2922, 3653, 7300], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "notification_email" {
  description = "Email address for receiving alarm notifications"
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "error_threshold" {
  description = "Number of errors that trigger an alarm"
  type        = number
  default     = 2
  
  validation {
    condition = var.error_threshold > 0 && var.error_threshold <= 100
    error_message = "Error threshold must be between 1 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for the alarm"
  type        = number
  default     = 1
  
  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "alarm_period_seconds" {
  description = "Period in seconds for alarm evaluation"
  type        = number
  default     = 300
  
  validation {
    condition = var.alarm_period_seconds >= 60 && var.alarm_period_seconds <= 86400
    error_message = "Alarm period must be between 60 and 86400 seconds."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "enable_lambda_insights" {
  description = "Enable Lambda Insights for enhanced monitoring"
  type        = bool
  default     = false
}

variable "metric_filter_patterns" {
  description = "List of patterns to match in log events for creating metrics"
  type        = list(string)
  default = [
    "ERROR",
    "FAILED", 
    "EXCEPTION",
    "TIMEOUT"
  ]
  
  validation {
    condition = length(var.metric_filter_patterns) > 0
    error_message = "At least one metric filter pattern must be provided."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}