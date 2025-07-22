# Core project variables
variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "textract-analysis"
  
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# S3 Configuration
variable "input_bucket_name" {
  description = "Name for the S3 input bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "output_bucket_name" {
  description = "Name for the S3 output bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "s3_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management"
  type        = bool
  default     = true
}

variable "s3_lifecycle_days" {
  description = "Number of days before transitioning objects to IA storage"
  type        = number
  default     = 30
}

# DynamoDB Configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used with PROVISIONED billing)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used with PROVISIONED billing)"
  type        = number
  default     = 5
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.lambda_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Step Functions Configuration
variable "step_functions_log_level" {
  description = "Step Functions execution log level"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_functions_log_level)
    error_message = "Step Functions log level must be one of: ALL, ERROR, FATAL, OFF."
  }
}

# SNS Configuration
variable "sns_email_endpoint" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
}

variable "sns_email_protocol" {
  description = "SNS subscription protocol"
  type        = string
  default     = "email"
}

# Security Configuration
variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "enable_dynamodb_encryption" {
  description = "Enable DynamoDB encryption at rest"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for API logging"
  type        = bool
  default     = false
}

# Monitoring Configuration
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_metric_namespace" {
  description = "CloudWatch custom metrics namespace"
  type        = string
  default     = "TextractAnalysis"
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}