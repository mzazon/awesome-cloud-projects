# Variables for EventBridge Archive and Replay Infrastructure
# This file defines all configurable parameters for the solution

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^(dev|staging|prod|demo)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "eventbridge-replay"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "event_bus_name" {
  description = "Name of the custom EventBridge event bus"
  type        = string
  default     = ""
}

variable "archive_name" {
  description = "Name of the EventBridge archive"
  type        = string
  default     = ""
}

variable "archive_retention_days" {
  description = "Number of days to retain events in the archive"
  type        = number
  default     = 30
  
  validation {
    condition     = var.archive_retention_days >= 1 && var.archive_retention_days <= 3653
    error_message = "Archive retention days must be between 1 and 3653 (10 years)."
  }
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for event processing"
  type        = string
  default     = ""
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for storing logs and artifacts"
  type        = string
  default     = ""
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications (optional)"
  type        = string
  default     = ""
}

variable "event_pattern_sources" {
  description = "List of event sources to include in the archive pattern"
  type        = list(string)
  default     = ["myapp.orders", "myapp.users", "myapp.inventory"]
}

variable "event_pattern_detail_types" {
  description = "List of event detail types to include in the archive pattern"
  type        = list(string)
  default     = ["Order Created", "User Registered", "Inventory Updated"]
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

variable "replication_region" {
  description = "AWS region for cross-region replication"
  type        = string
  default     = "us-west-2"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}