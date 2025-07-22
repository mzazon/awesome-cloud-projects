# Region Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Resource Naming
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "iot-data-visualization"
}

# IoT Configuration
variable "iot_topic_name" {
  description = "IoT topic name for sensor data"
  type        = string
  default     = "topic/sensor/data"
}

# Kinesis Configuration
variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis Data Stream"
  type        = number
  default     = 1
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 10
    error_message = "Kinesis shard count must be between 1 and 10."
  }
}

# Firehose Configuration
variable "firehose_buffer_size" {
  description = "Buffer size in MB for Kinesis Data Firehose"
  type        = number
  default     = 1
  
  validation {
    condition     = var.firehose_buffer_size >= 1 && var.firehose_buffer_size <= 128
    error_message = "Firehose buffer size must be between 1 and 128 MB."
  }
}

variable "firehose_buffer_interval" {
  description = "Buffer interval in seconds for Kinesis Data Firehose"
  type        = number
  default     = 60
  
  validation {
    condition     = var.firehose_buffer_interval >= 60 && var.firehose_buffer_interval <= 900
    error_message = "Firehose buffer interval must be between 60 and 900 seconds."
  }
}

# QuickSight Configuration
variable "quicksight_edition" {
  description = "QuickSight edition (STANDARD or ENTERPRISE)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "ENTERPRISE"], var.quicksight_edition)
    error_message = "QuickSight edition must be either STANDARD or ENTERPRISE."
  }
}

variable "quicksight_notification_email" {
  description = "Email address for QuickSight notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.quicksight_notification_email))
    error_message = "Please provide a valid email address."
  }
}

# S3 Configuration
variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_lifecycle_days" {
  description = "Number of days before moving objects to IA storage"
  type        = number
  default     = 30
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}