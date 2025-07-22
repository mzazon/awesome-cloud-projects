# Input Variables for Real-time Anomaly Detection Infrastructure
# This file defines all configurable parameters for the infrastructure deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
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
  default     = "anomaly-detection"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kinesis_stream_shard_count" {
  description = "Number of shards for the Kinesis Data Stream"
  type        = number
  default     = 2
  
  validation {
    condition     = var.kinesis_stream_shard_count >= 1 && var.kinesis_stream_shard_count <= 1000
    error_message = "Shard count must be between 1 and 1000."
  }
}

variable "kinesis_stream_retention_period" {
  description = "Data retention period in hours for Kinesis stream"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_stream_retention_period >= 24 && var.kinesis_stream_retention_period <= 8760
    error_message = "Retention period must be between 24 and 8760 hours."
  }
}

variable "flink_parallelism" {
  description = "Parallelism level for the Flink application"
  type        = number
  default     = 2
  
  validation {
    condition     = var.flink_parallelism >= 1 && var.flink_parallelism <= 64
    error_message = "Flink parallelism must be between 1 and 64."
  }
}

variable "flink_parallelism_per_kpu" {
  description = "Parallelism per KPU for the Flink application"
  type        = number
  default     = 1
  
  validation {
    condition     = var.flink_parallelism_per_kpu >= 1 && var.flink_parallelism_per_kpu <= 2
    error_message = "Parallelism per KPU must be between 1 and 2."
  }
}

variable "checkpoint_interval_ms" {
  description = "Checkpoint interval in milliseconds for Flink application"
  type        = number
  default     = 60000
  
  validation {
    condition     = var.checkpoint_interval_ms >= 5000 && var.checkpoint_interval_ms <= 600000
    error_message = "Checkpoint interval must be between 5000 and 600000 milliseconds."
  }
}

variable "anomaly_threshold_multiplier" {
  description = "Multiplier for anomaly detection threshold (e.g., 3 means 3x average)"
  type        = number
  default     = 3.0
  
  validation {
    condition     = var.anomaly_threshold_multiplier >= 1.5 && var.anomaly_threshold_multiplier <= 10.0
    error_message = "Anomaly threshold multiplier must be between 1.5 and 10.0."
  }
}

variable "notification_email" {
  description = "Email address for anomaly notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "s3_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "lambda_timeout_seconds" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for Kinesis streams"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}