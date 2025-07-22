# Input variables for Dead Letter Queue Processing infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 10
    error_message = "Environment must be between 1 and 10 characters."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "order-processing"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "main_queue_name" {
  description = "Name for the main SQS queue"
  type        = string
  default     = ""
}

variable "dlq_name" {
  description = "Name for the dead letter queue"
  type        = string
  default     = ""
}

variable "main_queue_visibility_timeout" {
  description = "Visibility timeout for main queue in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.main_queue_visibility_timeout >= 0 && var.main_queue_visibility_timeout <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds (12 hours)."
  }
}

variable "dlq_visibility_timeout" {
  description = "Visibility timeout for dead letter queue in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.dlq_visibility_timeout >= 0 && var.dlq_visibility_timeout <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds (12 hours)."
  }
}

variable "message_retention_period" {
  description = "Message retention period in seconds (1 minute to 14 days)"
  type        = number
  default     = 1209600 # 14 days

  validation {
    condition     = var.message_retention_period >= 60 && var.message_retention_period <= 1209600
    error_message = "Message retention period must be between 60 seconds (1 minute) and 1209600 seconds (14 days)."
  }
}

variable "max_receive_count" {
  description = "Maximum number of times a message can be received before being sent to DLQ"
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "Max receive count must be between 1 and 1000."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds (15 minutes)."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "dlq_monitor_timeout" {
  description = "DLQ monitor Lambda function timeout in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.dlq_monitor_timeout >= 1 && var.dlq_monitor_timeout <= 900
    error_message = "DLQ monitor timeout must be between 1 and 900 seconds (15 minutes)."
  }
}

variable "dlq_monitor_memory_size" {
  description = "DLQ monitor Lambda function memory size in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.dlq_monitor_memory_size >= 128 && var.dlq_monitor_memory_size <= 10240
    error_message = "DLQ monitor memory size must be between 128 and 10240 MB."
  }
}

variable "main_queue_batch_size" {
  description = "Number of messages to process in each Lambda invocation for main queue"
  type        = number
  default     = 10

  validation {
    condition     = var.main_queue_batch_size >= 1 && var.main_queue_batch_size <= 10000
    error_message = "Main queue batch size must be between 1 and 10000."
  }
}

variable "dlq_batch_size" {
  description = "Number of messages to process in each Lambda invocation for DLQ"
  type        = number
  default     = 5

  validation {
    condition     = var.dlq_batch_size >= 1 && var.dlq_batch_size <= 10000
    error_message = "DLQ batch size must be between 1 and 10000."
  }
}

variable "main_queue_batching_window" {
  description = "Maximum batching window in seconds for main queue"
  type        = number
  default     = 5

  validation {
    condition     = var.main_queue_batching_window >= 0 && var.main_queue_batching_window <= 300
    error_message = "Main queue batching window must be between 0 and 300 seconds."
  }
}

variable "dlq_batching_window" {
  description = "Maximum batching window in seconds for DLQ"
  type        = number
  default     = 10

  validation {
    condition     = var.dlq_batching_window >= 0 && var.dlq_batching_window <= 300
    error_message = "DLQ batching window must be between 0 and 300 seconds."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "dlq_alarm_threshold" {
  description = "Threshold for DLQ message count alarm"
  type        = number
  default     = 1

  validation {
    condition     = var.dlq_alarm_threshold >= 1
    error_message = "DLQ alarm threshold must be at least 1."
  }
}

variable "error_rate_alarm_threshold" {
  description = "Threshold for error rate alarm"
  type        = number
  default     = 5

  validation {
    condition     = var.error_rate_alarm_threshold >= 1
    error_message = "Error rate alarm threshold must be at least 1."
  }
}

variable "failure_simulation_rate" {
  description = "Failure simulation rate for demo purposes (0.0 to 1.0)"
  type        = number
  default     = 0.3

  validation {
    condition     = var.failure_simulation_rate >= 0.0 && var.failure_simulation_rate <= 1.0
    error_message = "Failure simulation rate must be between 0.0 and 1.0."
  }
}

variable "max_retry_attempts" {
  description = "Maximum retry attempts for high-value orders"
  type        = number
  default     = 5

  validation {
    condition     = var.max_retry_attempts >= 1 && var.max_retry_attempts <= 10
    error_message = "Max retry attempts must be between 1 and 10."
  }
}

variable "high_value_order_threshold" {
  description = "Order value threshold for high-value order processing"
  type        = number
  default     = 1000

  validation {
    condition     = var.high_value_order_threshold >= 0
    error_message = "High value order threshold must be a positive number."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}