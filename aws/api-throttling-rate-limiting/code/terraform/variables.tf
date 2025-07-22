# General Configuration
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "throttling-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.stage_name))
    error_message = "Stage name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "API-Throttling-Demo"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
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
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# API Gateway Stage-Level Throttling
variable "stage_throttle_rate_limit" {
  description = "Stage-level throttle rate limit (requests per second)"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.stage_throttle_rate_limit > 0
    error_message = "Stage throttle rate limit must be greater than 0."
  }
}

variable "stage_throttle_burst_limit" {
  description = "Stage-level throttle burst limit"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.stage_throttle_burst_limit > 0
    error_message = "Stage throttle burst limit must be greater than 0."
  }
}

# Premium Usage Plan Configuration
variable "premium_rate_limit" {
  description = "Premium usage plan rate limit (requests per second)"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.premium_rate_limit > 0
    error_message = "Premium rate limit must be greater than 0."
  }
}

variable "premium_burst_limit" {
  description = "Premium usage plan burst limit"
  type        = number
  default     = 5000
  
  validation {
    condition     = var.premium_burst_limit > 0
    error_message = "Premium burst limit must be greater than 0."
  }
}

variable "premium_quota_limit" {
  description = "Premium usage plan monthly quota"
  type        = number
  default     = 1000000
  
  validation {
    condition     = var.premium_quota_limit > 0
    error_message = "Premium quota limit must be greater than 0."
  }
}

# Standard Usage Plan Configuration
variable "standard_rate_limit" {
  description = "Standard usage plan rate limit (requests per second)"
  type        = number
  default     = 500
  
  validation {
    condition     = var.standard_rate_limit > 0
    error_message = "Standard rate limit must be greater than 0."
  }
}

variable "standard_burst_limit" {
  description = "Standard usage plan burst limit"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.standard_burst_limit > 0
    error_message = "Standard burst limit must be greater than 0."
  }
}

variable "standard_quota_limit" {
  description = "Standard usage plan monthly quota"
  type        = number
  default     = 100000
  
  validation {
    condition     = var.standard_quota_limit > 0
    error_message = "Standard quota limit must be greater than 0."
  }
}

# Basic Usage Plan Configuration
variable "basic_rate_limit" {
  description = "Basic usage plan rate limit (requests per second)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.basic_rate_limit > 0
    error_message = "Basic rate limit must be greater than 0."
  }
}

variable "basic_burst_limit" {
  description = "Basic usage plan burst limit"
  type        = number
  default     = 200
  
  validation {
    condition     = var.basic_burst_limit > 0
    error_message = "Basic burst limit must be greater than 0."
  }
}

variable "basic_quota_limit" {
  description = "Basic usage plan monthly quota"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.basic_quota_limit > 0
    error_message = "Basic quota limit must be greater than 0."
  }
}

# CloudWatch Monitoring Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "throttling_alarm_threshold" {
  description = "Threshold for throttling alarm (count)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.throttling_alarm_threshold > 0
    error_message = "Throttling alarm threshold must be greater than 0."
  }
}

variable "error_alarm_threshold" {
  description = "Threshold for 4xx error alarm (count)"
  type        = number
  default     = 50
  
  validation {
    condition     = var.error_alarm_threshold > 0
    error_message = "Error alarm threshold must be greater than 0."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "Alarm evaluation periods must be at least 1."
  }
}

variable "alarm_period" {
  description = "Period for alarm evaluation in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = contains([60, 300, 900, 3600], var.alarm_period)
    error_message = "Alarm period must be one of: 60, 300, 900, 3600 seconds."
  }
}