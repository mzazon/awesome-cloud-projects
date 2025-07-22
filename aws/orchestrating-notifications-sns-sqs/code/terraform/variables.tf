# AWS Configuration
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Project Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "notification-system"
}

variable "random_suffix" {
  description = "Random suffix for unique resource names"
  type        = string
  default     = ""
}

# SNS Configuration
variable "sns_topic_name" {
  description = "Name of the SNS topic"
  type        = string
  default     = "notifications"
}

# SQS Configuration
variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds"
  type        = number
  default     = 300
}

variable "sqs_message_retention_period" {
  description = "SQS message retention period in seconds"
  type        = number
  default     = 1209600 # 14 days
}

variable "sqs_max_receive_count" {
  description = "Maximum number of times a message can be received before being sent to DLQ"
  type        = number
  default     = 3
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
}

# Event Source Mapping Configuration
variable "event_source_batch_size" {
  description = "Maximum number of messages to process in a single batch"
  type        = number
  default     = 10
}

variable "event_source_max_batching_window" {
  description = "Maximum batching window in seconds"
  type        = number
  default     = 5
}

# Notification Configuration
variable "test_email" {
  description = "Test email address for notifications"
  type        = string
  default     = "your-email@example.com"
}

variable "webhook_url" {
  description = "Default webhook URL for testing"
  type        = string
  default     = "https://httpbin.org/post"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}