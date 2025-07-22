# Environment configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

# Resource naming
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "document-processing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# S3 bucket configuration
variable "document_bucket_name" {
  description = "Name for the document storage bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "results_bucket_name" {
  description = "Name for the results storage bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "enable_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_days" {
  description = "Number of days to retain objects in S3 buckets"
  type        = number
  default     = 90
  
  validation {
    condition     = var.bucket_lifecycle_days >= 1 && var.bucket_lifecycle_days <= 365
    error_message = "Lifecycle days must be between 1 and 365."
  }
}

# Lambda configuration
variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = can(regex("^python3\\.[0-9]+$", var.lambda_runtime))
    error_message = "Lambda runtime must be in format python3.x."
  }
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
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# DynamoDB configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used with PROVISIONED billing mode)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

# SNS configuration
variable "notification_email" {
  description = "Email address for SNS notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

# Step Functions configuration
variable "step_functions_log_level" {
  description = "Step Functions execution log level"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_functions_log_level)
    error_message = "Step Functions log level must be ALL, ERROR, FATAL, or OFF."
  }
}

# Document processing configuration
variable "supported_file_extensions" {
  description = "List of supported file extensions for processing"
  type        = list(string)
  default     = [".pdf", ".png", ".jpg", ".jpeg", ".tiff", ".tif"]
  
  validation {
    condition     = length(var.supported_file_extensions) > 0
    error_message = "At least one file extension must be specified."
  }
}

variable "max_retry_attempts" {
  description = "Maximum number of retry attempts for failed processing"
  type        = number
  default     = 3
  
  validation {
    condition     = var.max_retry_attempts >= 1 && var.max_retry_attempts <= 10
    error_message = "Max retry attempts must be between 1 and 10."
  }
}

variable "retry_interval_seconds" {
  description = "Initial retry interval in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.retry_interval_seconds >= 1 && var.retry_interval_seconds <= 60
    error_message = "Retry interval must be between 1 and 60 seconds."
  }
}

variable "retry_backoff_rate" {
  description = "Backoff rate for retry attempts"
  type        = number
  default     = 2.0
  
  validation {
    condition     = var.retry_backoff_rate >= 1.0 && var.retry_backoff_rate <= 10.0
    error_message = "Retry backoff rate must be between 1.0 and 10.0."
  }
}

# Security configuration
variable "enable_s3_encryption" {
  description = "Enable S3 server-side encryption"
  type        = bool
  default     = true
}

variable "enable_dynamodb_encryption" {
  description = "Enable DynamoDB encryption at rest"
  type        = bool
  default     = true
}

variable "enable_sns_encryption" {
  description = "Enable SNS topic encryption"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Monitoring configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda and Step Functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Cost optimization
variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = true
}

variable "transition_to_ia_days" {
  description = "Number of days before transitioning to Infrequent Access"
  type        = number
  default     = 30
  
  validation {
    condition     = var.transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "transition_to_glacier_days" {
  description = "Number of days before transitioning to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition     = var.transition_to_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}