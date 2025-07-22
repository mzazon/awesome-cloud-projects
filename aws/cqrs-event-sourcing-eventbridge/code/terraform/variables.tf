# Input Variables for CQRS Event Sourcing Infrastructure
# These variables allow customization of the deployment without modifying the main configuration

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "cqrs-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# DynamoDB Configuration
variable "event_store_read_capacity" {
  description = "Read capacity units for the event store table"
  type        = number
  default     = 10
  
  validation {
    condition     = var.event_store_read_capacity >= 1 && var.event_store_read_capacity <= 1000
    error_message = "Read capacity must be between 1 and 1000."
  }
}

variable "event_store_write_capacity" {
  description = "Write capacity units for the event store table"
  type        = number
  default     = 10
  
  validation {
    condition     = var.event_store_write_capacity >= 1 && var.event_store_write_capacity <= 1000
    error_message = "Write capacity must be between 1 and 1000."
  }
}

variable "read_model_read_capacity" {
  description = "Read capacity units for read model tables"
  type        = number
  default     = 5
  
  validation {
    condition     = var.read_model_read_capacity >= 1 && var.read_model_read_capacity <= 1000
    error_message = "Read capacity must be between 1 and 1000."
  }
}

variable "read_model_write_capacity" {
  description = "Write capacity units for read model tables"
  type        = number
  default     = 5
  
  validation {
    condition     = var.read_model_write_capacity >= 1 && var.read_model_write_capacity <= 1000
    error_message = "Write capacity must be between 1 and 1000."
  }
}

variable "gsi_read_capacity" {
  description = "Read capacity units for Global Secondary Indexes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.gsi_read_capacity >= 1 && var.gsi_read_capacity <= 1000
    error_message = "GSI read capacity must be between 1 and 1000."
  }
}

variable "gsi_write_capacity" {
  description = "Write capacity units for Global Secondary Indexes"
  type        = number
  default     = 5
  
  validation {
    condition     = var.gsi_write_capacity >= 1 && var.gsi_write_capacity <= 1000
    error_message = "GSI write capacity must be between 1 and 1000."
  }
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition     = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# EventBridge Configuration
variable "event_archive_retention_days" {
  description = "Number of days to retain events in the EventBridge archive"
  type        = number
  default     = 30
  
  validation {
    condition     = var.event_archive_retention_days >= 1 && var.event_archive_retention_days <= 365
    error_message = "Archive retention must be between 1 and 365 days."
  }
}

variable "stream_batch_size" {
  description = "Batch size for DynamoDB Stream processing"
  type        = number
  default     = 10
  
  validation {
    condition     = var.stream_batch_size >= 1 && var.stream_batch_size <= 100
    error_message = "Stream batch size must be between 1 and 100."
  }
}

# Resource Naming Configuration
variable "enable_random_suffix" {
  description = "Enable random suffix for resource names to ensure uniqueness"
  type        = bool
  default     = true
}

variable "random_suffix_length" {
  description = "Length of the random suffix"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10 characters."
  }
}

# Monitoring and Logging
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for Lambda functions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention value."
  }
}