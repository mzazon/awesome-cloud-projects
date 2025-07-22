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
  default     = "stream-enrichment"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.project_name))
    error_message = "Project name must be 3-30 characters, lowercase alphanumeric and hyphens only."
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

# S3 Configuration
variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket name (bucket will be {prefix}-{random_id})"
  type        = string
  default     = "stream-enrichment-data"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{3,50}$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must be 3-50 characters, lowercase alphanumeric and hyphens only."
  }
}

variable "s3_data_prefix" {
  description = "Prefix for enriched data objects in S3"
  type        = string
  default     = "enriched-data"
}

variable "s3_error_prefix" {
  description = "Prefix for error data objects in S3"
  type        = string
  default     = "error-data"
}

# Kinesis Configuration
variable "kinesis_stream_mode" {
  description = "Kinesis Data Stream capacity mode (ON_DEMAND or PROVISIONED)"
  type        = string
  default     = "ON_DEMAND"
  
  validation {
    condition     = contains(["ON_DEMAND", "PROVISIONED"], var.kinesis_stream_mode)
    error_message = "Kinesis stream mode must be either ON_DEMAND or PROVISIONED."
  }
}

variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis Data Stream (only used if mode is PROVISIONED)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 1000
    error_message = "Kinesis shard count must be between 1 and 1000."
  }
}

variable "kinesis_retention_period" {
  description = "Kinesis Data Stream retention period in hours"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Kinesis retention period must be between 24 and 8760 hours (1 year)."
  }
}

# Firehose Configuration
variable "firehose_buffer_size" {
  description = "Firehose buffer size in MB"
  type        = number
  default     = 5
  
  validation {
    condition     = var.firehose_buffer_size >= 1 && var.firehose_buffer_size <= 128
    error_message = "Firehose buffer size must be between 1 and 128 MB."
  }
}

variable "firehose_buffer_interval" {
  description = "Firehose buffer interval in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.firehose_buffer_interval >= 60 && var.firehose_buffer_interval <= 900
    error_message = "Firehose buffer interval must be between 60 and 900 seconds."
  }
}

variable "firehose_compression_format" {
  description = "Compression format for Firehose delivery (GZIP, ZIP, Snappy, HADOOP_SNAPPY, or UNCOMPRESSED)"
  type        = string
  default     = "GZIP"
  
  validation {
    condition     = contains(["GZIP", "ZIP", "Snappy", "HADOOP_SNAPPY", "UNCOMPRESSED"], var.firehose_compression_format)
    error_message = "Compression format must be one of: GZIP, ZIP, Snappy, HADOOP_SNAPPY, UNCOMPRESSED."
  }
}

# Lambda Configuration
variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
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

variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.11"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# DynamoDB Configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB table"
  type        = bool
  default     = true
}

# EventBridge Pipes Configuration
variable "pipes_batch_size" {
  description = "Batch size for EventBridge Pipes"
  type        = number
  default     = 10
  
  validation {
    condition     = var.pipes_batch_size >= 1 && var.pipes_batch_size <= 100
    error_message = "Pipes batch size must be between 1 and 100."
  }
}

variable "pipes_maximum_batching_window_in_seconds" {
  description = "Maximum batching window for EventBridge Pipes in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.pipes_maximum_batching_window_in_seconds >= 0 && var.pipes_maximum_batching_window_in_seconds <= 300
    error_message = "Pipes maximum batching window must be between 0 and 300 seconds."
  }
}

variable "pipes_starting_position" {
  description = "Starting position for EventBridge Pipes (LATEST, TRIM_HORIZON, AT_TIMESTAMP)"
  type        = string
  default     = "LATEST"
  
  validation {
    condition     = contains(["LATEST", "TRIM_HORIZON", "AT_TIMESTAMP"], var.pipes_starting_position)
    error_message = "Pipes starting position must be one of: LATEST, TRIM_HORIZON, AT_TIMESTAMP."
  }
}

# Sample Data Configuration
variable "populate_sample_data" {
  description = "Whether to populate DynamoDB with sample reference data"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Logs for Lambda function"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch retention periods."
  }
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for all supported resources"
  type        = bool
  default     = true
}