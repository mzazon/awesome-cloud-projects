variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "webhook-processing"
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}

variable "sqs_message_retention_seconds" {
  description = "The number of seconds SQS retains messages"
  type        = number
  default     = 1209600 # 14 days
  
  validation {
    condition     = var.sqs_message_retention_seconds >= 60 && var.sqs_message_retention_seconds <= 1209600
    error_message = "Message retention must be between 60 seconds and 14 days."
  }
}

variable "sqs_visibility_timeout_seconds" {
  description = "The visibility timeout for SQS messages"
  type        = number
  default     = 300 # 5 minutes
  
  validation {
    condition     = var.sqs_visibility_timeout_seconds >= 0 && var.sqs_visibility_timeout_seconds <= 43200
    error_message = "Visibility timeout must be between 0 and 12 hours."
  }
}

variable "max_receive_count" {
  description = "Maximum number of times a message can be received before moving to DLQ"
  type        = number
  default     = 3
  
  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "Max receive count must be between 1 and 1000."
  }
}

variable "lambda_timeout_seconds" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
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

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "sqs_batch_size" {
  description = "Maximum number of messages to batch for Lambda processing"
  type        = number
  default     = 10
  
  validation {
    condition     = var.sqs_batch_size >= 1 && var.sqs_batch_size <= 10000
    error_message = "Batch size must be between 1 and 10000."
  }
}

variable "sqs_maximum_batching_window_in_seconds" {
  description = "Maximum amount of time to wait for messages to batch"
  type        = number
  default     = 5
  
  validation {
    condition     = var.sqs_maximum_batching_window_in_seconds >= 0 && var.sqs_maximum_batching_window_in_seconds <= 300
    error_message = "Maximum batching window must be between 0 and 300 seconds."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB table read capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB table write capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

variable "api_gateway_stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "Number of periods over which data is compared to the specified threshold"
  type        = number
  default     = 1
  
  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1
    error_message = "Evaluation periods must be at least 1."
  }
}

variable "cloudwatch_alarm_period_seconds" {
  description = "The period in seconds over which the specified statistic is applied"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cloudwatch_alarm_period_seconds >= 60
    error_message = "Alarm period must be at least 60 seconds."
  }
}

variable "dlq_alarm_threshold" {
  description = "Threshold for DLQ alarm (number of messages)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.dlq_alarm_threshold >= 1
    error_message = "DLQ alarm threshold must be at least 1."
  }
}

variable "lambda_error_alarm_threshold" {
  description = "Threshold for Lambda error alarm (number of errors)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.lambda_error_alarm_threshold >= 1
    error_message = "Lambda error alarm threshold must be at least 1."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}