# Input variables for the Comprehend Custom Entity Recognition and Classification infrastructure
# These variables allow customization of the deployment

variable "project_name" {
  description = "Name of the project - used as prefix for resource names"
  type        = string
  default     = "comprehend-custom"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only alphanumeric characters and hyphens, and end with alphanumeric character."
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_force_destroy" {
  description = "Force destroy S3 bucket even if it contains objects (use with caution)"
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for training data and model artifacts"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable S3 bucket encryption using AWS managed keys"
  type        = bool
  default     = true
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
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "step_functions_log_level" {
  description = "Log level for Step Functions (ALL, ERROR, FATAL, OFF)"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_functions_log_level)
    error_message = "Step Functions log level must be one of: ALL, ERROR, FATAL, OFF."
  }
}

variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
}

variable "api_gateway_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (requests per second)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.api_gateway_throttle_rate_limit > 0
    error_message = "API Gateway throttle rate limit must be greater than 0."
  }
}

variable "api_gateway_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 200
  
  validation {
    condition     = var.api_gateway_throttle_burst_limit > 0
    error_message = "API Gateway throttle burst limit must be greater than 0."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "enable_cloudwatch_logs_retention" {
  description = "Enable CloudWatch logs retention"
  type        = bool
  default     = true
}

variable "cloudwatch_logs_retention_days" {
  description = "CloudWatch logs retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_logs_retention_days)
    error_message = "CloudWatch logs retention days must be a valid retention period."
  }
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for training completion"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for SNS notifications (required if enable_sns_notifications is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_api_gateway_logging" {
  description = "Enable API Gateway access logging"
  type        = bool
  default     = true
}

variable "comprehend_language_code" {
  description = "Language code for Comprehend models (en, es, fr, de, it, pt, ar, hi, ja, ko, zh, zh-TW)"
  type        = string
  default     = "en"
  
  validation {
    condition = contains([
      "en", "es", "fr", "de", "it", "pt", "ar", "hi", "ja", "ko", "zh", "zh-TW"
    ], var.comprehend_language_code)
    error_message = "Language code must be a supported Comprehend language."
  }
}

variable "custom_tags" {
  description = "Additional custom tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_monitoring_dashboard" {
  description = "Enable CloudWatch monitoring dashboard"
  type        = bool
  default     = true
}