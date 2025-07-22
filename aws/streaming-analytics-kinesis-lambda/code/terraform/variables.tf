# Variable definitions for serverless real-time analytics pipeline
# These variables allow customization of the deployment

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "realtime-analytics"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "kinesis_shard_count" {
  description = "Number of shards for the Kinesis Data Stream"
  type        = number
  default     = 2

  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 1000
    error_message = "Shard count must be between 1 and 1000."
  }
}

variable "kinesis_retention_period" {
  description = "Data retention period in hours (24-8760)"
  type        = number
  default     = 24

  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Retention period must be between 24 and 8760 hours."
  }
}

variable "lambda_memory_size" {
  description = "Amount of memory available to the Lambda function at runtime"
  type        = number
  default     = 512

  validation {
    condition = contains([
      128, 192, 256, 320, 384, 448, 512, 576, 640, 704, 768, 832, 896, 960,
      1024, 1088, 1152, 1216, 1280, 1344, 1408, 1472, 1536, 1600, 1664, 1728,
      1792, 1856, 1920, 1984, 2048, 2112, 2176, 2240, 2304, 2368, 2432, 2496,
      2560, 2624, 2688, 2752, 2816, 2880, 2944, 3008
    ], var.lambda_memory_size)
    error_message = "Lambda memory size must be a valid value between 128 MB and 3008 MB."
  }
}

variable "lambda_timeout" {
  description = "Amount of time Lambda function has to run in seconds"
  type        = number
  default     = 300

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
    error_message = "Batch size must be between 1 and 10000."
  }
}

variable "lambda_maximum_batching_window" {
  description = "Maximum amount of time to gather records before invoking Lambda (seconds)"
  type        = number
  default     = 5

  validation {
    condition     = var.lambda_maximum_batching_window >= 0 && var.lambda_maximum_batching_window <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "Billing mode must be either PROVISIONED or PAY_PER_REQUEST."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_email_endpoint" {
  description = "Email address for CloudWatch alarm notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.alarm_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alarm_email_endpoint))
    error_message = "Email endpoint must be a valid email address or empty string."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}