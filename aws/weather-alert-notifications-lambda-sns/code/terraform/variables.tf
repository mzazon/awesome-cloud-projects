# Input variables for the weather alert notifications infrastructure
# These variables allow customization of the deployment without modifying the main configuration

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-west-2, eu-west-1, etc."
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

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "weather-alerts"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "city" {
  description = "City for weather monitoring"
  type        = string
  default     = "Seattle"

  validation {
    condition     = length(var.city) > 0
    error_message = "City name cannot be empty."
  }
}

variable "temperature_threshold" {
  description = "Temperature threshold in Fahrenheit for alerts"
  type        = number
  default     = 32

  validation {
    condition     = var.temperature_threshold >= -50 && var.temperature_threshold <= 150
    error_message = "Temperature threshold must be between -50 and 150 degrees Fahrenheit."
  }
}

variable "wind_threshold" {
  description = "Wind speed threshold in mph for alerts"
  type        = number
  default     = 25

  validation {
    condition     = var.wind_threshold >= 0 && var.wind_threshold <= 200
    error_message = "Wind threshold must be between 0 and 200 mph."
  }
}

variable "weather_api_key" {
  description = "OpenWeatherMap API key (optional - uses demo data if not provided)"
  type        = string
  default     = "demo_key"
  sensitive   = true
}

variable "notification_email" {
  description = "Email address for weather notifications"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for weather checks"
  type        = string
  default     = "rate(1 hour)"

  validation {
    condition = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.schedule_expression))
    error_message = "Schedule expression must be a valid EventBridge rate or cron expression."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 128

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.tags : can(regex("^[a-zA-Z0-9\\s_.:/=+@-]{1,128}$", k))
    ])
    error_message = "Tag keys must be 1-128 characters and contain only letters, numbers, spaces, and the characters _.:/=+@-"
  }
}