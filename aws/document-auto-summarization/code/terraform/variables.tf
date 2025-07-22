# Core configuration variables
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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
  description = "Name of the project for resource naming"
  type        = string
  default     = "doc-summarizer"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 bucket configuration
variable "input_bucket_name" {
  description = "Name for the input documents S3 bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "output_bucket_name" {
  description = "Name for the output summaries S3 bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_enabled" {
  description = "Enable lifecycle management for S3 buckets"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_days" {
  description = "Number of days after which to transition objects to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.bucket_lifecycle_days >= 30
    error_message = "Lifecycle days must be at least 30 for IA transition."
  }
}

# Lambda function configuration
variable "lambda_function_name" {
  description = "Name for the Lambda function (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
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

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# Bedrock configuration
variable "bedrock_model_id" {
  description = "Amazon Bedrock model ID for text summarization"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
  
  validation {
    condition = can(regex("^anthropic\\.|^amazon\\.|^cohere\\.|^ai21\\.", var.bedrock_model_id))
    error_message = "Bedrock model ID must be a valid model identifier."
  }
}

variable "bedrock_max_tokens" {
  description = "Maximum tokens for Bedrock model response"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.bedrock_max_tokens >= 100 && var.bedrock_max_tokens <= 4000
    error_message = "Bedrock max tokens must be between 100 and 4000."
  }
}

# Monitoring and alerting
variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for processing events"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for SNS notifications (required if enable_sns_notifications is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.enable_sns_notifications == false || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "A valid email address is required when SNS notifications are enabled."
  }
}

# Security configuration
variable "enable_bucket_encryption" {
  description = "Enable server-side encryption for S3 buckets"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 10
  
  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Document processing configuration
variable "supported_document_types" {
  description = "List of supported document file extensions"
  type        = list(string)
  default     = ["pdf", "txt", "docx", "png", "jpg", "jpeg"]
}

variable "max_document_size_mb" {
  description = "Maximum document size in MB for processing"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_document_size_mb >= 1 && var.max_document_size_mb <= 100
    error_message = "Maximum document size must be between 1 and 100 MB."
  }
}

variable "document_prefix" {
  description = "S3 key prefix for organizing input documents"
  type        = string
  default     = "documents/"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]+/$", var.document_prefix))
    error_message = "Document prefix must end with a forward slash and contain only alphanumeric characters, underscores, hyphens, and forward slashes."
  }
}

# Cost optimization
variable "enable_lambda_reserved_concurrency" {
  description = "Enable reserved concurrency for Lambda function"
  type        = bool
  default     = false
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function"
  type        = number
  default     = 10
  
  validation {
    condition     = var.lambda_reserved_concurrency >= 1 && var.lambda_reserved_concurrency <= 1000
    error_message = "Lambda reserved concurrency must be between 1 and 1000."
  }
}