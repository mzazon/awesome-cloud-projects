# Variables for Real-Time IoT Analytics Infrastructure
# This file defines all configurable parameters for the IoT analytics pipeline

# General Configuration
variable "project_name" {
  description = "Name of the project - used for resource naming"
  type        = string
  default     = "iot-analytics"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# Kinesis Configuration
variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis Data Stream"
  type        = number
  default     = 2
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 100
    error_message = "Shard count must be between 1 and 100."
  }
}

variable "kinesis_retention_period" {
  description = "Data retention period for Kinesis stream in hours"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 168
    error_message = "Retention period must be between 24 and 168 hours."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime environment for Lambda functions"
  type        = string
  default     = "python3.11"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_batch_size" {
  description = "Batch size for Lambda event source mapping"
  type        = number
  default     = 10
  
  validation {
    condition     = var.lambda_batch_size >= 1 && var.lambda_batch_size <= 10000
    error_message = "Lambda batch size must be between 1 and 10000."
  }
}

variable "lambda_batch_window" {
  description = "Maximum batching window for Lambda in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.lambda_batch_window >= 0 && var.lambda_batch_window <= 300
    error_message = "Lambda batch window must be between 0 and 300 seconds."
  }
}

# Flink Configuration
variable "flink_runtime_environment" {
  description = "Runtime environment for Flink application"
  type        = string
  default     = "FLINK-1_18"
  
  validation {
    condition     = contains(["FLINK-1_18", "FLINK-1_19"], var.flink_runtime_environment)
    error_message = "Flink runtime environment must be a supported version."
  }
}

variable "flink_parallelism" {
  description = "Parallelism level for Flink application"
  type        = number
  default     = 1
  
  validation {
    condition     = var.flink_parallelism >= 1 && var.flink_parallelism <= 64
    error_message = "Flink parallelism must be between 1 and 64."
  }
}

variable "flink_checkpoint_interval" {
  description = "Checkpoint interval for Flink application in milliseconds"
  type        = number
  default     = 60000
  
  validation {
    condition     = var.flink_checkpoint_interval >= 5000 && var.flink_checkpoint_interval <= 3600000
    error_message = "Flink checkpoint interval must be between 5000 and 3600000 milliseconds."
  }
}

# S3 Configuration
variable "s3_versioning_enabled" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle management for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Days after which objects transition to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_transition_to_ia_days >= 1
    error_message = "Transition to IA days must be at least 1."
  }
}

variable "s3_transition_to_glacier_days" {
  description = "Days after which objects transition to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_transition_to_glacier_days >= 1
    error_message = "Transition to Glacier days must be at least 1."
  }
}

variable "s3_expiration_days" {
  description = "Days after which objects expire and are deleted"
  type        = number
  default     = 365
  
  validation {
    condition     = var.s3_expiration_days >= 1
    error_message = "Expiration days must be at least 1."
  }
}

# SNS Configuration
variable "alert_email" {
  description = "Email address for SNS alerts"
  type        = string
  default     = ""
  
  validation {
    condition     = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "Log retention period for CloudWatch logs in days"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for resources"
  type        = bool
  default     = true
}

# Alarm Configuration
variable "kinesis_records_threshold" {
  description = "Threshold for Kinesis records alarm"
  type        = number
  default     = 100
  
  validation {
    condition     = var.kinesis_records_threshold >= 1
    error_message = "Kinesis records threshold must be at least 1."
  }
}

variable "lambda_errors_threshold" {
  description = "Threshold for Lambda errors alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.lambda_errors_threshold >= 1
    error_message = "Lambda errors threshold must be at least 1."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "Alarm evaluation periods must be at least 1."
  }
}

# Anomaly Detection Configuration
variable "temperature_threshold" {
  description = "Temperature threshold for anomaly detection"
  type        = number
  default     = 80.0
}

variable "pressure_threshold" {
  description = "Pressure threshold for anomaly detection"
  type        = number
  default     = 100.0
}

variable "vibration_threshold" {
  description = "Vibration threshold for anomaly detection"
  type        = number
  default     = 50.0
}

variable "flow_threshold" {
  description = "Flow threshold for anomaly detection"
  type        = number
  default     = 75.0
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}