# Input variables for the clickstream analytics infrastructure

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "clickstream-analytics"

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
    condition = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 100
    error_message = "Kinesis shard count must be between 1 and 100."
  }
}

variable "kinesis_retention_period" {
  description = "Data retention period for Kinesis stream in hours"
  type        = number
  default     = 24

  validation {
    condition = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Kinesis retention period must be between 24 and 8760 hours."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60

  validation {
    condition = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "batch_size" {
  description = "Batch size for Lambda event source mapping"
  type        = number
  default     = 100

  validation {
    condition = var.batch_size >= 1 && var.batch_size <= 10000
    error_message = "Batch size must be between 1 and 10000."
  }
}

variable "maximum_batching_window_in_seconds" {
  description = "Maximum batching window for Lambda event source mapping"
  type        = number
  default     = 5

  validation {
    condition = var.maximum_batching_window_in_seconds >= 0 && var.maximum_batching_window_in_seconds <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

variable "enable_anomaly_detection" {
  description = "Enable anomaly detection Lambda function"
  type        = bool
  default     = true
}

variable "enable_sns_alerts" {
  description = "Enable SNS topic for anomaly alerts"
  type        = bool
  default     = false
}

variable "sns_email_endpoint" {
  description = "Email address for SNS alerts (if enabled)"
  type        = string
  default     = ""
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which S3 objects expire"
  type        = number
  default     = 30

  validation {
    condition = var.s3_lifecycle_expiration_days >= 1 && var.s3_lifecycle_expiration_days <= 3653
    error_message = "S3 lifecycle expiration must be between 1 and 3653 days."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}