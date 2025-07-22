# variables.tf - Input variables for the Comprehend NLP solution

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1", "ap-southeast-1",
      "ap-southeast-2", "ap-northeast-1", "ca-central-1"
    ], var.aws_region)
    error_message = "AWS region must be one of the supported regions for Amazon Comprehend."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z]+$", var.environment))
    error_message = "Environment must be lowercase letters only."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "nlp-comprehend"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]+$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
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

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names (will be combined with random suffix)"
  type        = string
  default     = "comprehend-nlp"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must start with a letter or number and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption on S3 buckets"
  type        = bool
  default     = true
}

variable "enable_eventbridge_processing" {
  description = "Enable EventBridge automation for S3 object creation"
  type        = bool
  default     = true
}

variable "comprehend_language_code" {
  description = "Language code for Comprehend processing"
  type        = string
  default     = "en"
  
  validation {
    condition = contains([
      "en", "es", "fr", "de", "it", "pt", "ar", "hi", "ja", "ko", "zh", "zh-TW"
    ], var.comprehend_language_code)
    error_message = "Language code must be one of the supported Comprehend languages."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention periods."
  }
}

variable "enable_custom_entity_training" {
  description = "Enable custom entity recognizer training resources"
  type        = bool
  default     = false
}

variable "custom_entity_types" {
  description = "List of custom entity types for training"
  type        = list(string)
  default     = ["PRODUCT", "BRAND", "FEATURE"]
}

variable "topics_detection_number" {
  description = "Number of topics to detect in topic modeling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.topics_detection_number >= 1 && var.topics_detection_number <= 100
    error_message = "Number of topics must be between 1 and 100."
  }
}

variable "notification_email" {
  description = "Email address for job completion notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_batch_processing" {
  description = "Enable batch processing jobs for large datasets"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}