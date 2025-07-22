# Input Variables for Savings Plans Recommendations Infrastructure
# This file defines all configurable parameters for the infrastructure deployment

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in format: us-east-1, eu-west-1, etc."
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
  default     = "savings-plans-analyzer"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for Savings Plans analysis"
  type        = string
  default     = "savings-plans-analyzer"
  
  validation {
    condition = length(var.lambda_function_name) <= 64
    error_message = "Lambda function name must be 64 characters or less."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function execution in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 512
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for storing cost recommendations (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "s3_bucket_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_bucket_lifecycle_days" {
  description = "Number of days after which objects transition to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition = var.s3_bucket_lifecycle_days >= 1 && var.s3_bucket_lifecycle_days <= 365
    error_message = "S3 lifecycle days must be between 1 and 365."
  }
}

variable "eventbridge_schedule_enabled" {
  description = "Enable EventBridge scheduled rule for automated analysis"
  type        = bool
  default     = true
}

variable "eventbridge_schedule_expression" {
  description = "EventBridge schedule expression for automated analysis"
  type        = string
  default     = "rate(30 days)"
  
  validation {
    condition = can(regex("^(rate|cron)\\(.*\\)$", var.eventbridge_schedule_expression))
    error_message = "EventBridge schedule expression must be in format: rate(30 days) or cron(0 0 1 * ? *)."
  }
}

variable "cloudwatch_dashboard_enabled" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid value (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653)."
  }
}

variable "lambda_analysis_parameters" {
  description = "Default parameters for Savings Plans analysis"
  type = object({
    lookback_days   = string
    term_years      = string
    payment_option  = string
  })
  default = {
    lookback_days  = "SIXTY_DAYS"
    term_years     = "ONE_YEAR"
    payment_option = "NO_UPFRONT"
  }
  
  validation {
    condition = contains(["SEVEN_DAYS", "THIRTY_DAYS", "SIXTY_DAYS"], var.lambda_analysis_parameters.lookback_days)
    error_message = "Lookback days must be one of: SEVEN_DAYS, THIRTY_DAYS, SIXTY_DAYS."
  }
  
  validation {
    condition = contains(["ONE_YEAR", "THREE_YEARS"], var.lambda_analysis_parameters.term_years)
    error_message = "Term years must be one of: ONE_YEAR, THREE_YEARS."
  }
  
  validation {
    condition = contains(["NO_UPFRONT", "PARTIAL_UPFRONT", "ALL_UPFRONT"], var.lambda_analysis_parameters.payment_option)
    error_message = "Payment option must be one of: NO_UPFRONT, PARTIAL_UPFRONT, ALL_UPFRONT."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}