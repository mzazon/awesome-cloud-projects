# Core configuration variables
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "nlp-comprehend-pipeline"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# S3 bucket configuration
variable "enable_s3_versioning" {
  description = "Enable versioning for S3 buckets"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle management for S3 buckets"
  type        = bool
  default     = true
}

variable "s3_transition_days" {
  description = "Number of days after which objects transition to IA storage class"
  type        = number
  default     = 30
}

variable "s3_expiration_days" {
  description = "Number of days after which objects are deleted"
  type        = number
  default     = 365
}

# Lambda function configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (set to -1 for no limit)"
  type        = number
  default     = 10
}

# CloudWatch Logs configuration
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# Amazon Comprehend configuration
variable "comprehend_language_code" {
  description = "Default language code for Comprehend analysis"
  type        = string
  default     = "en"
  
  validation {
    condition = contains([
      "en", "es", "fr", "de", "it", "pt", "ar", "hi", "ja", "ko", "zh", "zh-TW"
    ], var.comprehend_language_code)
    error_message = "Language code must be supported by Amazon Comprehend."
  }
}

variable "enable_custom_classification" {
  description = "Enable custom document classification model training"
  type        = bool
  default     = true
}

variable "training_data_format" {
  description = "Format of training data for custom classification"
  type        = string
  default     = "COMPREHEND_CSV"
  
  validation {
    condition     = contains(["COMPREHEND_CSV", "AUGMENTED_MANIFEST"], var.training_data_format)
    error_message = "Training data format must be either COMPREHEND_CSV or AUGMENTED_MANIFEST."
  }
}

# Security and access configuration
variable "enable_kms_encryption" {
  description = "Enable KMS encryption for S3 buckets and Lambda environment variables"
  type        = bool
  default     = true
}

variable "allowed_source_ips" {
  description = "List of IP addresses allowed to invoke Lambda function directly (CIDR notation)"
  type        = list(string)
  default     = []
}

# Monitoring and alerting configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring and alerting"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
}

# Cost optimization settings
variable "enable_s3_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for cost optimization"
  type        = bool
  default     = true
}

variable "lambda_provisioned_concurrency" {
  description = "Provisioned concurrency for Lambda function (0 to disable)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.lambda_provisioned_concurrency >= 0
    error_message = "Provisioned concurrency must be greater than or equal to 0."
  }
}

# Tagging configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}