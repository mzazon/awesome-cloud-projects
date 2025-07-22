# Project Configuration
variable "project_name" {
  description = "Name of the video analytics project"
  type        = string
  default     = "video-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
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

# Video Stream Configuration
variable "video_stream_name" {
  description = "Name of the Kinesis Video Stream"
  type        = string
  default     = ""
}

variable "video_retention_hours" {
  description = "Data retention period for video streams in hours"
  type        = number
  default     = 24
  
  validation {
    condition     = var.video_retention_hours >= 1 && var.video_retention_hours <= 8760
    error_message = "Video retention must be between 1 and 8760 hours (1 year)."
  }
}

variable "video_media_type" {
  description = "Media type for video streams"
  type        = string
  default     = "video/h264"
  
  validation {
    condition     = contains(["video/h264", "video/h265"], var.video_media_type)
    error_message = "Media type must be either video/h264 or video/h265."
  }
}

# Face Recognition Configuration
variable "face_collection_name" {
  description = "Name of the Rekognition face collection"
  type        = string
  default     = ""
}

variable "face_match_threshold" {
  description = "Similarity threshold for face matching (0-100)"
  type        = number
  default     = 80.0
  
  validation {
    condition     = var.face_match_threshold >= 0 && var.face_match_threshold <= 100
    error_message = "Face match threshold must be between 0 and 100."
  }
}

# Stream Processing Configuration
variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis Data Stream"
  type        = number
  default     = 2
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 1000
    error_message = "Shard count must be between 1 and 1000."
  }
}

variable "lambda_batch_size" {
  description = "Batch size for Lambda event source mapping"
  type        = number
  default     = 10
  
  validation {
    condition     = var.lambda_batch_size >= 1 && var.lambda_batch_size <= 100
    error_message = "Lambda batch size must be between 1 and 100."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

# DynamoDB Configuration
variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB tables"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB tables"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

# Alerting Configuration
variable "alert_email" {
  description = "Email address for security alerts (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

variable "enable_api_gateway" {
  description = "Enable API Gateway for video analytics queries"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for data at rest and in transit"
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

# Monitoring Configuration
variable "enable_cloudwatch_insights" {
  description = "Enable CloudWatch Logs Insights for Lambda functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

# Resource Naming
variable "resource_name_suffix" {
  description = "Optional suffix for resource names (auto-generated if empty)"
  type        = string
  default     = ""
}