# Variables for Event-Driven Architecture with Amazon EventBridge

#------------------------------------------------------------------------------
# Project Configuration
#------------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "eventbridge-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "custom_bus_name" {
  description = "Base name for the custom EventBridge event bus (will have random suffix appended)"
  type        = string
  default     = "ecommerce-events"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_.]+$", var.custom_bus_name))
    error_message = "Custom bus name must contain only alphanumeric characters, hyphens, underscores, and periods."
  }
}

#------------------------------------------------------------------------------
# Lambda Function Configuration
#------------------------------------------------------------------------------

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size in MB for Lambda functions"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

#------------------------------------------------------------------------------
# CloudWatch Configuration
#------------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for Lambda functions"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# SQS Configuration
#------------------------------------------------------------------------------

variable "sqs_delay_seconds" {
  description = "Time in seconds that delivery of messages is delayed for SQS queue"
  type        = number
  default     = 30
  
  validation {
    condition     = var.sqs_delay_seconds >= 0 && var.sqs_delay_seconds <= 900
    error_message = "SQS delay seconds must be between 0 and 900."
  }
}

variable "sqs_visibility_timeout" {
  description = "Visibility timeout in seconds for SQS messages"
  type        = number
  default     = 300
  
  validation {
    condition     = var.sqs_visibility_timeout >= 0 && var.sqs_visibility_timeout <= 43200
    error_message = "SQS visibility timeout must be between 0 and 43200 seconds (12 hours)."
  }
}

variable "sqs_message_retention" {
  description = "Number of seconds SQS retains messages"
  type        = number
  default     = 1209600  # 14 days
  
  validation {
    condition     = var.sqs_message_retention >= 60 && var.sqs_message_retention <= 1209600
    error_message = "SQS message retention must be between 60 seconds and 1209600 seconds (14 days)."
  }
}

variable "sqs_max_receive_count" {
  description = "Maximum number of times a message can be received before moving to DLQ"
  type        = number
  default     = 3
  
  validation {
    condition     = var.sqs_max_receive_count >= 1 && var.sqs_max_receive_count <= 1000
    error_message = "SQS max receive count must be between 1 and 1000."
  }
}

#------------------------------------------------------------------------------
# EventBridge Configuration
#------------------------------------------------------------------------------

variable "enable_event_bus_kms_encryption" {
  description = "Enable KMS encryption for EventBridge event bus"
  type        = bool
  default     = false
}

variable "event_bus_kms_key_id" {
  description = "KMS key ID for EventBridge event bus encryption (only used if enable_event_bus_kms_encryption is true)"
  type        = string
  default     = null
}

variable "enable_event_replay" {
  description = "Enable event replay capability for EventBridge"
  type        = bool
  default     = false
}

variable "event_source_mapping_batch_size" {
  description = "Maximum number of events to include in each batch for Lambda event source mapping"
  type        = number
  default     = 10
  
  validation {
    condition     = var.event_source_mapping_batch_size >= 1 && var.event_source_mapping_batch_size <= 1000
    error_message = "Event source mapping batch size must be between 1 and 1000."
  }
}

#------------------------------------------------------------------------------
# Security Configuration
#------------------------------------------------------------------------------

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency limit for Lambda functions (null for unreserved)"
  type        = number
  default     = null
  
  validation {
    condition = var.lambda_reserved_concurrency == null || (
      var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000
    )
    error_message = "Lambda reserved concurrency must be between 0 and 1000, or null for unreserved."
  }
}

variable "enable_vpc_config" {
  description = "Enable VPC configuration for Lambda functions"
  type        = bool
  default     = false
}

variable "vpc_subnet_ids" {
  description = "VPC subnet IDs for Lambda functions (only used if enable_vpc_config is true)"
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "VPC security group IDs for Lambda functions (only used if enable_vpc_config is true)"
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Tagging Configuration
#------------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.tags : can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]*$", key))
    ])
    error_message = "Tag keys must contain only valid characters."
  }
}

#------------------------------------------------------------------------------
# Advanced Configuration
#------------------------------------------------------------------------------

variable "enable_dead_letter_queue" {
  description = "Enable dead letter queue for SQS payment processing queue"
  type        = bool
  default     = true
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for EventBridge (requires additional configuration)"
  type        = bool
  default     = false
}

variable "replication_regions" {
  description = "List of AWS regions for cross-region EventBridge replication"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for region in var.replication_regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", region))
    ])
    error_message = "All regions must be valid AWS region names (e.g., us-east-1, eu-west-1)."
  }
}

variable "enable_event_archive" {
  description = "Enable event archiving for EventBridge events"
  type        = bool
  default     = false
}

variable "event_archive_retention_days" {
  description = "Number of days to retain archived events"
  type        = number
  default     = 365
  
  validation {
    condition     = var.event_archive_retention_days >= 1 && var.event_archive_retention_days <= 3653
    error_message = "Event archive retention must be between 1 and 3653 days (10 years)."
  }
}

#------------------------------------------------------------------------------
# Performance Configuration
#------------------------------------------------------------------------------

variable "lambda_provisioned_concurrency" {
  description = "Provisioned concurrency for Lambda functions (null to disable)"
  type        = number
  default     = null
  
  validation {
    condition = var.lambda_provisioned_concurrency == null || (
      var.lambda_provisioned_concurrency >= 1 && var.lambda_provisioned_concurrency <= 1000
    )
    error_message = "Lambda provisioned concurrency must be between 1 and 1000, or null to disable."
  }
}

variable "enable_lambda_insights" {
  description = "Enable Lambda Insights enhanced monitoring"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Cost Optimization Configuration
#------------------------------------------------------------------------------

variable "lambda_architecture" {
  description = "Instruction set architecture for Lambda functions"
  type        = string
  default     = "x86_64"
  
  validation {
    condition     = contains(["x86_64", "arm64"], var.lambda_architecture)
    error_message = "Lambda architecture must be either x86_64 or arm64."
  }
}

variable "enable_cost_allocation_tags" {
  description = "Enable additional cost allocation tags for detailed billing analysis"
  type        = bool
  default     = true
}

#------------------------------------------------------------------------------
# Testing Configuration
#------------------------------------------------------------------------------

variable "enable_test_events" {
  description = "Deploy test event generator Lambda function for testing the architecture"
  type        = bool
  default     = true
}

variable "test_event_schedule" {
  description = "Schedule expression for automated test event generation (empty to disable)"
  type        = string
  default     = ""
  
  validation {
    condition = var.test_event_schedule == "" || can(
      regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\([^)]+\\))$", var.test_event_schedule)
    )
    error_message = "Test event schedule must be a valid EventBridge schedule expression or empty string."
  }
}

#------------------------------------------------------------------------------
# Development Configuration
#------------------------------------------------------------------------------

variable "enable_debug_logging" {
  description = "Enable debug logging for Lambda functions"
  type        = bool
  default     = false
}

variable "lambda_environment_variables" {
  description = "Additional environment variables for Lambda functions"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.lambda_environment_variables : can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", key))
    ])
    error_message = "Environment variable keys must start with a letter or underscore and contain only alphanumeric characters and underscores."
  }
}