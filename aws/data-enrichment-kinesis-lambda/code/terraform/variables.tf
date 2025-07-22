# variables.tf - Input variables for the streaming data enrichment infrastructure

variable "aws_region" {
  description = "The AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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
  default     = "data-enrichment"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kinesis_shard_count" {
  description = "Number of shards for the Kinesis Data Stream"
  type        = number
  default     = 2

  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 100
    error_message = "Kinesis shard count must be between 1 and 100."
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

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_batch_size" {
  description = "Number of records to process in each Lambda invocation"
  type        = number
  default     = 10

  validation {
    condition     = var.lambda_batch_size >= 1 && var.lambda_batch_size <= 10000
    error_message = "Lambda batch size must be between 1 and 10000."
  }
}

variable "lambda_maximum_batching_window_in_seconds" {
  description = "Maximum amount of time to gather records before invoking the function"
  type        = number
  default     = 5

  validation {
    condition     = var.lambda_maximum_batching_window_in_seconds >= 0 && var.lambda_maximum_batching_window_in_seconds <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

variable "s3_versioning_enabled" {
  description = "Enable versioning on the S3 bucket"
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

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring for Kinesis stream"
  type        = bool
  default     = true
}

variable "cloudwatch_alarms_enabled" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid value."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}