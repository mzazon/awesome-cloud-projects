# AWS Region
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

# Environment designation
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Resource naming suffix
variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
}

# Event store configuration
variable "event_store_read_capacity" {
  description = "Read capacity units for the event store DynamoDB table"
  type        = number
  default     = 10
}

variable "event_store_write_capacity" {
  description = "Write capacity units for the event store DynamoDB table"
  type        = number
  default     = 10
}

variable "event_store_gsi_read_capacity" {
  description = "Read capacity units for the event store GSI"
  type        = number
  default     = 5
}

variable "event_store_gsi_write_capacity" {
  description = "Write capacity units for the event store GSI"
  type        = number
  default     = 5
}

# Read model configuration
variable "read_model_read_capacity" {
  description = "Read capacity units for the read model DynamoDB table"
  type        = number
  default     = 5
}

variable "read_model_write_capacity" {
  description = "Write capacity units for the read model DynamoDB table"
  type        = number
  default     = 5
}

# Lambda function configuration
variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 128
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
}

# Event archive configuration
variable "event_archive_retention_days" {
  description = "Number of days to retain events in the archive"
  type        = number
  default     = 365
}

# Dead letter queue configuration
variable "dlq_message_retention_seconds" {
  description = "Message retention period in seconds for dead letter queue"
  type        = number
  default     = 1209600 # 14 days
}

variable "dlq_visibility_timeout_seconds" {
  description = "Visibility timeout in seconds for dead letter queue"
  type        = number
  default     = 300
}

# CloudWatch alarms configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of periods for CloudWatch alarm evaluation"
  type        = number
  default     = 2
}

variable "alarm_period_seconds" {
  description = "Period in seconds for CloudWatch alarm evaluation"
  type        = number
  default     = 300
}