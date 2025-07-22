# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "fifo-processing"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# SQS Configuration Variables
variable "main_queue_visibility_timeout" {
  description = "Visibility timeout for the main FIFO queue in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.main_queue_visibility_timeout >= 0 && var.main_queue_visibility_timeout <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds (12 hours)."
  }
}

variable "dlq_visibility_timeout" {
  description = "Visibility timeout for the dead letter queue in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.dlq_visibility_timeout >= 0 && var.dlq_visibility_timeout <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds (12 hours)."
  }
}

variable "message_retention_period" {
  description = "Message retention period in seconds (1 minute to 14 days)"
  type        = number
  default     = 1209600 # 14 days
  
  validation {
    condition = var.message_retention_period >= 60 && var.message_retention_period <= 1209600
    error_message = "Message retention period must be between 60 seconds (1 minute) and 1209600 seconds (14 days)."
  }
}

variable "max_receive_count" {
  description = "Maximum number of receives before sending message to dead letter queue"
  type        = number
  default     = 3
  
  validation {
    condition = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "Max receive count must be between 1 and 1000."
  }
}

# Lambda Configuration Variables
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds (15 minutes)."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for message processor Lambda"
  type        = number
  default     = 10
  
  validation {
    condition = var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000
    error_message = "Reserved concurrency must be between 0 and 1000."
  }
}

variable "processor_batch_size" {
  description = "Batch size for message processor event source mapping"
  type        = number
  default     = 1
  
  validation {
    condition = var.processor_batch_size >= 1 && var.processor_batch_size <= 10
    error_message = "Batch size must be between 1 and 10 for FIFO queues."
  }
}

variable "poison_handler_batch_size" {
  description = "Batch size for poison message handler event source mapping"
  type        = number
  default     = 5
  
  validation {
    condition = var.poison_handler_batch_size >= 1 && var.poison_handler_batch_size <= 10
    error_message = "Batch size must be between 1 and 10 for FIFO queues."
  }
}

variable "maximum_batching_window" {
  description = "Maximum batching window in seconds for Lambda event source mapping"
  type        = number
  default     = 5
  
  validation {
    condition = var.maximum_batching_window >= 0 && var.maximum_batching_window <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

# DynamoDB Configuration Variables
variable "dynamodb_read_capacity" {
  description = "DynamoDB table read capacity units"
  type        = number
  default     = 10
  
  validation {
    condition = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB table write capacity units"
  type        = number
  default     = 10
  
  validation {
    condition = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "gsi_read_capacity" {
  description = "Global Secondary Index read capacity units"
  type        = number
  default     = 5
  
  validation {
    condition = var.gsi_read_capacity >= 1
    error_message = "GSI read capacity must be at least 1."
  }
}

variable "gsi_write_capacity" {
  description = "Global Secondary Index write capacity units"
  type        = number
  default     = 5
  
  validation {
    condition = var.gsi_write_capacity >= 1
    error_message = "GSI write capacity must be at least 1."
  }
}

# S3 Configuration Variables
variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 archive bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_standard_ia_days" {
  description = "Number of days after which to transition objects to Standard-IA"
  type        = number
  default     = 30
  
  validation {
    condition = var.s3_lifecycle_standard_ia_days >= 1
    error_message = "Standard-IA transition days must be at least 1."
  }
}

variable "s3_lifecycle_glacier_days" {
  description = "Number of days after which to transition objects to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition = var.s3_lifecycle_glacier_days >= 1
    error_message = "Glacier transition days must be at least 1."
  }
}

# CloudWatch Configuration Variables
variable "failure_rate_threshold" {
  description = "Threshold for high failure rate alarm"
  type        = number
  default     = 5
  
  validation {
    condition = var.failure_rate_threshold >= 1
    error_message = "Failure rate threshold must be at least 1."
  }
}

variable "latency_threshold_ms" {
  description = "Threshold for high processing latency alarm in milliseconds"
  type        = number
  default     = 5000
  
  validation {
    condition = var.latency_threshold_ms >= 100
    error_message = "Latency threshold must be at least 100 milliseconds."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition = var.alarm_evaluation_periods >= 1
    error_message = "Evaluation periods must be at least 1."
  }
}

# Notification Configuration Variables
variable "notification_email" {
  description = "Email address for SNS notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Resource Naming Variables
variable "resource_suffix" {
  description = "Optional suffix for resource names (auto-generated if not provided)"
  type        = string
  default     = ""
}

# Security Variables
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for SQS queues and S3 bucket"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}