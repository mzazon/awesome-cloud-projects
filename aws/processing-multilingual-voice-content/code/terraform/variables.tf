# Variables for multi-language voice processing pipeline
# This file defines all configurable parameters for the infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "voice-pipeline"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for enhanced observability"
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
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "s3_bucket_force_destroy" {
  description = "Allow Terraform to destroy S3 buckets even if they contain objects"
  type        = bool
  default     = false
}

variable "s3_bucket_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

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
  description = "DynamoDB read capacity units (only used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used when billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "target_languages" {
  description = "List of target languages for translation (ISO 639-1 codes)"
  type        = list(string)
  default     = ["es", "fr", "de", "pt", "it", "ja", "ko", "zh", "ar", "hi"]
  
  validation {
    condition = alltrue([
      for lang in var.target_languages : can(regex("^[a-z]{2}(-[A-Z]{2})?$", lang))
    ])
    error_message = "Target languages must be valid ISO 639-1 codes (e.g., 'es', 'fr', 'zh-CN')."
  }
}

variable "enable_dead_letter_queue" {
  description = "Enable dead letter queue for failed processing jobs"
  type        = bool
  default     = true
}

variable "step_function_logging_level" {
  description = "Step Functions state machine logging level"
  type        = string
  default     = "ERROR"
  
  validation {
    condition     = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_function_logging_level)
    error_message = "Step Functions logging level must be one of: ALL, ERROR, FATAL, OFF."
  }
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_retention_days)
    error_message = "CloudWatch retention days must be a valid value."
  }
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for job completion and errors"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "transcribe_custom_vocabulary" {
  description = "Enable custom vocabulary for improved transcription accuracy"
  type        = bool
  default     = false
}

variable "translate_custom_terminology" {
  description = "Enable custom terminology for consistent translation"
  type        = bool
  default     = false
}

variable "enable_api_gateway" {
  description = "Enable API Gateway for web interface and external integrations"
  type        = bool
  default     = true
}

variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "v1"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "enable_cors" {
  description = "Enable CORS for API Gateway endpoints"
  type        = bool
  default     = true
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS"
  type        = list(string)
  default     = ["*"]
}

variable "enable_x_ray_tracing" {
  description = "Enable AWS X-Ray tracing for distributed tracing"
  type        = bool
  default     = true
}

variable "polly_voice_preferences" {
  description = "Voice preferences for each language in Polly"
  type        = map(string)
  default = {
    "en"    = "Joanna"
    "es"    = "Lupe"
    "fr"    = "Lea"
    "de"    = "Vicki"
    "it"    = "Bianca"
    "pt"    = "Camila"
    "ja"    = "Takumi"
    "ko"    = "Seoyeon"
    "zh"    = "Zhiyu"
    "ar"    = "Zeina"
    "hi"    = "Aditi"
    "ru"    = "Tatyana"
    "nl"    = "Lotte"
    "sv"    = "Astrid"
  }
}

variable "enable_encryption" {
  description = "Enable encryption at rest for all supported services"
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

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}