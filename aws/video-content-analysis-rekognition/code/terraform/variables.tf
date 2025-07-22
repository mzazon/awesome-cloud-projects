# Variables for Video Content Analysis Infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
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
  default     = "video-analysis"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
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

variable "aggregation_lambda_timeout" {
  description = "Aggregation Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.aggregation_lambda_timeout >= 60 && var.aggregation_lambda_timeout <= 900
    error_message = "Aggregation Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "aggregation_lambda_memory_size" {
  description = "Aggregation Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.aggregation_lambda_memory_size >= 128 && var.aggregation_lambda_memory_size <= 10240
    error_message = "Aggregation Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units"
  type        = number
  default     = 10
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 1000
    error_message = "DynamoDB read capacity must be between 1 and 1000 units."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units"
  type        = number
  default     = 10
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 1000
    error_message = "DynamoDB write capacity must be between 1 and 1000 units."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning objects to IA storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_transition_days >= 30
    error_message = "S3 lifecycle transition days must be at least 30 days."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before expiring objects (0 to disable)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 0
    error_message = "S3 lifecycle expiration days must be 0 or greater."
  }
}

variable "rekognition_min_confidence" {
  description = "Minimum confidence score for Rekognition detections"
  type        = number
  default     = 50.0
  
  validation {
    condition     = var.rekognition_min_confidence >= 0 && var.rekognition_min_confidence <= 100
    error_message = "Rekognition minimum confidence must be between 0 and 100."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for Lambda functions"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid AWS retention period."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}