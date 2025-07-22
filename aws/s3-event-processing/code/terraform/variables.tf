# Variables for event-driven data processing infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "data-processing"
}

variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "The notification_email must be a valid email address."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (will be made unique with random suffix)"
  type        = string
  default     = "data-processing"
}

variable "data_processing_timeout" {
  description = "Timeout for data processing Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.data_processing_timeout >= 60 && var.data_processing_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "data_processing_memory" {
  description = "Memory allocation for data processing Lambda function in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.data_processing_memory >= 128 && var.data_processing_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "error_handler_timeout" {
  description = "Timeout for error handler Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.error_handler_timeout >= 30 && var.error_handler_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "error_handler_memory" {
  description = "Memory allocation for error handler Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.error_handler_memory >= 128 && var.error_handler_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "dlq_visibility_timeout" {
  description = "Visibility timeout for Dead Letter Queue in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.dlq_visibility_timeout >= 0 && var.dlq_visibility_timeout <= 43200
    error_message = "DLQ visibility timeout must be between 0 and 43200 seconds."
  }
}

variable "dlq_message_retention" {
  description = "Message retention period for Dead Letter Queue in seconds"
  type        = number
  default     = 1209600 # 14 days
  
  validation {
    condition     = var.dlq_message_retention >= 60 && var.dlq_message_retention <= 1209600
    error_message = "DLQ message retention must be between 60 and 1209600 seconds."
  }
}

variable "cloudwatch_log_retention" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention)
    error_message = "CloudWatch log retention must be one of: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "data_prefix" {
  description = "S3 prefix for data files that should trigger processing"
  type        = string
  default     = "data/"
}

variable "supported_file_types" {
  description = "List of supported file types for processing"
  type        = list(string)
  default     = [".csv", ".json", ".txt"]
}

variable "enable_encryption" {
  description = "Enable encryption for S3 bucket and SQS queue"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}