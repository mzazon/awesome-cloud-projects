# Input Variables for Real-time Data Processing Infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "realtime-data-processing"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kinesis_stream_name" {
  description = "Name for the Kinesis Data Stream"
  type        = string
  default     = "realtime-data-stream"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+$", var.kinesis_stream_name))
    error_message = "Kinesis stream name must contain only alphanumeric characters, underscores, periods, and hyphens."
  }
}

variable "kinesis_shard_count" {
  description = "Number of shards for the Kinesis stream"
  type        = number
  default     = 3

  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 100
    error_message = "Kinesis shard count must be between 1 and 100."
  }
}

variable "kinesis_retention_period" {
  description = "Data retention period for Kinesis stream (in hours)"
  type        = number
  default     = 24

  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Kinesis retention period must be between 24 hours (1 day) and 8760 hours (365 days)."
  }
}

variable "lambda_function_name" {
  description = "Name for the Lambda function"
  type        = string
  default     = "kinesis-data-processor"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_name))
    error_message = "Lambda function name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.11"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function (in MB)"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function (in seconds)"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_batch_size" {
  description = "Maximum number of records to send to Lambda in a single batch"
  type        = number
  default     = 100

  validation {
    condition     = var.lambda_batch_size >= 1 && var.lambda_batch_size <= 10000
    error_message = "Lambda batch size must be between 1 and 10000."
  }
}

variable "lambda_maximum_batching_window" {
  description = "Maximum time to wait for filling batch (in seconds)"
  type        = number
  default     = 5

  validation {
    condition     = var.lambda_maximum_batching_window >= 0 && var.lambda_maximum_batching_window <= 300
    error_message = "Lambda maximum batching window must be between 0 and 300 seconds."
  }
}

variable "s3_bucket_suffix" {
  description = "Suffix for S3 bucket name (bucket will be {project-name}-processed-data-{suffix})"
  type        = string
  default     = ""
}

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

variable "s3_transition_ia_days" {
  description = "Number of days after which objects transition to Infrequent Access"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_transition_ia_days >= 30
    error_message = "S3 IA transition must be at least 30 days."
  }
}

variable "s3_transition_glacier_days" {
  description = "Number of days after which objects transition to Glacier"
  type        = number
  default     = 90

  validation {
    condition     = var.s3_transition_glacier_days >= 30
    error_message = "S3 Glacier transition must be at least 30 days."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring and detailed CloudWatch metrics"
  type        = bool
  default     = false
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda function"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}