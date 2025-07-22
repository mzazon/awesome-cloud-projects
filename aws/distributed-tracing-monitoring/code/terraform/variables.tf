# Variables for AWS X-Ray Infrastructure Monitoring

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "xray-monitoring"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "random_suffix" {
  description = "Random suffix for unique resource naming"
  type        = string
  default     = ""
}

# DynamoDB Configuration
variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB table"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 1000
    error_message = "DynamoDB read capacity must be between 1 and 1000."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB table"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 1000
    error_message = "DynamoDB write capacity must be between 1 and 1000."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"

  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 128

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# X-Ray Configuration
variable "xray_sampling_rate" {
  description = "X-Ray sampling rate (0.0 to 1.0)"
  type        = number
  default     = 0.1

  validation {
    condition     = var.xray_sampling_rate >= 0.0 && var.xray_sampling_rate <= 1.0
    error_message = "X-Ray sampling rate must be between 0.0 and 1.0."
  }
}

variable "xray_reservoir_size" {
  description = "X-Ray reservoir size for sampling"
  type        = number
  default     = 5

  validation {
    condition     = var.xray_reservoir_size >= 0 && var.xray_reservoir_size <= 100
    error_message = "X-Ray reservoir size must be between 0 and 100."
  }
}

# CloudWatch Configuration
variable "enable_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alarm_error_threshold" {
  description = "Error count threshold for CloudWatch alarm"
  type        = number
  default     = 5

  validation {
    condition     = var.alarm_error_threshold >= 1
    error_message = "Error threshold must be at least 1."
  }
}

variable "alarm_latency_threshold" {
  description = "High latency count threshold for CloudWatch alarm"
  type        = number
  default     = 3

  validation {
    condition     = var.alarm_latency_threshold >= 1
    error_message = "Latency threshold must be at least 1."
  }
}

# EventBridge Configuration
variable "trace_analysis_schedule" {
  description = "Schedule expression for automated trace analysis"
  type        = string
  default     = "rate(1 hour)"

  validation {
    condition     = can(regex("^(rate\\(.*\\)|cron\\(.*\\))$", var.trace_analysis_schedule))
    error_message = "Schedule must be a valid rate or cron expression."
  }
}

# API Gateway Configuration
variable "api_gateway_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.api_gateway_stage_name))
    error_message = "Stage name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for alarm notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}