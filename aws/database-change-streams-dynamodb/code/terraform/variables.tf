# Variables for DynamoDB Streams real-time processing infrastructure

variable "environment" {
  description = "Environment name (e.g., development, staging, production)"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "stream-processing"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "table_name" {
  description = "Name of the DynamoDB table for user activities"
  type        = string
  default     = "UserActivities"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-_]*$", var.table_name))
    error_message = "Table name must start with a letter and contain only letters, numbers, hyphens, and underscores."
  }
}

variable "read_capacity" {
  description = "The number of read units for the DynamoDB table"
  type        = number
  default     = 5

  validation {
    condition     = var.read_capacity >= 1 && var.read_capacity <= 40000
    error_message = "Read capacity must be between 1 and 40000."
  }
}

variable "write_capacity" {
  description = "The number of write units for the DynamoDB table"
  type        = number
  default     = 5

  validation {
    condition     = var.write_capacity >= 1 && var.write_capacity <= 40000
    error_message = "Write capacity must be between 1 and 40000."
  }
}

variable "stream_view_type" {
  description = "When an item in the table is modified, determines what information is written to the stream"
  type        = string
  default     = "NEW_AND_OLD_IMAGES"

  validation {
    condition = contains([
      "KEYS_ONLY",
      "NEW_IMAGE",
      "OLD_IMAGE",
      "NEW_AND_OLD_IMAGES"
    ], var.stream_view_type)
    error_message = "Stream view type must be one of: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, NEW_AND_OLD_IMAGES."
  }
}

variable "lambda_runtime" {
  description = "Runtime environment for the Lambda function"
  type        = string
  default     = "python3.9"

  validation {
    condition = contains([
      "python3.8",
      "python3.9",
      "python3.10",
      "python3.11",
      "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_memory_size" {
  description = "Amount of memory in MB allocated to the Lambda function"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Memory size must be between 128 MB and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "The amount of time your Lambda function has to run in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Timeout must be between 1 and 900 seconds."
  }
}

variable "batch_size" {
  description = "The largest number of records that Lambda will retrieve from your event source at the time of invoking your function"
  type        = number
  default     = 10

  validation {
    condition     = var.batch_size >= 1 && var.batch_size <= 1000
    error_message = "Batch size must be between 1 and 1000."
  }
}

variable "maximum_batching_window_in_seconds" {
  description = "The maximum amount of time to gather records before invoking the function, in seconds"
  type        = number
  default     = 5

  validation {
    condition     = var.maximum_batching_window_in_seconds >= 0 && var.maximum_batching_window_in_seconds <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

variable "maximum_record_age_in_seconds" {
  description = "The maximum age of a record that Lambda sends to a function for processing"
  type        = number
  default     = 3600

  validation {
    condition     = var.maximum_record_age_in_seconds >= 60 && var.maximum_record_age_in_seconds <= 604800
    error_message = "Maximum record age must be between 60 seconds (1 minute) and 604800 seconds (7 days)."
  }
}

variable "maximum_retry_attempts" {
  description = "The maximum number of times to retry when the function returns an error"
  type        = number
  default     = 3

  validation {
    condition     = var.maximum_retry_attempts >= 0 && var.maximum_retry_attempts <= 10000
    error_message = "Maximum retry attempts must be between 0 and 10000."
  }
}

variable "parallelization_factor" {
  description = "The number of batches to process from each shard concurrently"
  type        = number
  default     = 2

  validation {
    condition     = var.parallelization_factor >= 1 && var.parallelization_factor <= 10
    error_message = "Parallelization factor must be between 1 and 10."
  }
}

variable "dlq_message_retention_period" {
  description = "The number of seconds Amazon SQS retains a message in the dead letter queue"
  type        = number
  default     = 1209600 # 14 days

  validation {
    condition     = var.dlq_message_retention_period >= 60 && var.dlq_message_retention_period <= 1209600
    error_message = "Message retention period must be between 60 seconds and 1209600 seconds (14 days)."
  }
}

variable "enable_email_notifications" {
  description = "Whether to enable email notifications for alerts"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for SNS notifications (required if enable_email_notifications is true)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Specifies the number of days you want to retain log events in the CloudWatch Logs group"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be one of the supported values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for audit logs (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 audit bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days after which objects are transitioned to IA storage class"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_lifecycle_transition_days >= 30
    error_message = "S3 lifecycle transition days must be at least 30."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}