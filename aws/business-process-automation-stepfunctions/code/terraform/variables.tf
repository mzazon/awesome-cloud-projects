# AWS Configuration
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# Project Configuration
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "business-process"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 128
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# Step Functions Configuration
variable "step_functions_log_level" {
  description = "Step Functions logging level"
  type        = string
  default     = "ERROR"
  
  validation {
    condition = contains(["ALL", "ERROR", "FATAL", "OFF"], var.step_functions_log_level)
    error_message = "Step Functions log level must be ALL, ERROR, FATAL, or OFF."
  }
}

variable "human_approval_timeout" {
  description = "Human approval timeout in seconds (max 86400 for 24 hours)"
  type        = number
  default     = 86400
  
  validation {
    condition = var.human_approval_timeout >= 3600 && var.human_approval_timeout <= 86400
    error_message = "Human approval timeout must be between 1 hour (3600s) and 24 hours (86400s)."
  }
}

variable "heartbeat_timeout" {
  description = "Heartbeat timeout for human approval in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition = var.heartbeat_timeout >= 60 && var.heartbeat_timeout <= 3600
    error_message = "Heartbeat timeout must be between 1 minute (60s) and 1 hour (3600s)."
  }
}

# SQS Configuration
variable "sqs_visibility_timeout" {
  description = "SQS queue visibility timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.sqs_visibility_timeout >= 0 && var.sqs_visibility_timeout <= 43200
    error_message = "SQS visibility timeout must be between 0 and 43200 seconds."
  }
}

variable "sqs_message_retention_seconds" {
  description = "SQS message retention period in seconds"
  type        = number
  default     = 1209600 # 14 days
  
  validation {
    condition = var.sqs_message_retention_seconds >= 60 && var.sqs_message_retention_seconds <= 1209600
    error_message = "SQS message retention must be between 60 seconds and 14 days (1209600 seconds)."
  }
}

# SNS Configuration
variable "notification_email" {
  description = "Email address for process notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# API Gateway Configuration
variable "api_gateway_stage_name" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# Resource Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Security Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for resources"
  type        = bool
  default     = false
}