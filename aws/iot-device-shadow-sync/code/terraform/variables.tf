# AWS Region configuration
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name."
  }
}

# Random suffix for unique resource naming
variable "random_suffix" {
  description = "Random suffix for resource names to ensure uniqueness"
  type        = string
  default     = ""
}

# IoT Thing configuration
variable "thing_name_prefix" {
  description = "Prefix for IoT Thing name"
  type        = string
  default     = "sync-demo-device"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9_-]+$", var.thing_name_prefix))
    error_message = "Thing name prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "thing_type_name" {
  description = "IoT Thing Type name"
  type        = string
  default     = "SyncDemoDevice"
}

# Lambda function configuration
variable "conflict_resolver_timeout" {
  description = "Timeout for conflict resolver Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.conflict_resolver_timeout >= 1 && var.conflict_resolver_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "conflict_resolver_memory" {
  description = "Memory allocation for conflict resolver Lambda function in MB"
  type        = number
  default     = 512
  
  validation {
    condition = var.conflict_resolver_memory >= 128 && var.conflict_resolver_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "sync_manager_timeout" {
  description = "Timeout for sync manager Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.sync_manager_timeout >= 1 && var.sync_manager_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "sync_manager_memory" {
  description = "Memory allocation for sync manager Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.sync_manager_memory >= 128 && var.sync_manager_memory <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

# DynamoDB configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PAY_PER_REQUEST or PROVISIONED)"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5
}

# EventBridge configuration
variable "health_check_schedule" {
  description = "Schedule expression for health checks (EventBridge rate syntax)"
  type        = string
  default     = "rate(15 minutes)"
  
  validation {
    condition = can(regex("^rate\\(.*\\)$|^cron\\(.*\\)$", var.health_check_schedule))
    error_message = "Schedule expression must be in EventBridge rate() or cron() format."
  }
}

# CloudWatch configuration
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Shadow configuration
variable "shadow_names" {
  description = "List of named shadows to create for the demo device"
  type        = list(string)
  default     = ["configuration", "telemetry", "maintenance"]
  
  validation {
    condition = length(var.shadow_names) > 0 && length(var.shadow_names) <= 10
    error_message = "Must specify between 1 and 10 shadow names."
  }
}

# Conflict resolution configuration
variable "default_conflict_strategy" {
  description = "Default conflict resolution strategy"
  type        = string
  default     = "field_level_merge"
  
  validation {
    condition = contains(["last_writer_wins", "field_level_merge", "priority_based", "manual_review"], var.default_conflict_strategy)
    error_message = "Conflict strategy must be one of: last_writer_wins, field_level_merge, priority_based, manual_review."
  }
}

variable "auto_resolve_threshold" {
  description = "Number of conflicts before requiring manual review"
  type        = number
  default     = 5
  
  validation {
    condition = var.auto_resolve_threshold >= 1 && var.auto_resolve_threshold <= 100
    error_message = "Auto resolve threshold must be between 1 and 100."
  }
}

# Device configuration
variable "device_attributes" {
  description = "Attributes for the demo IoT device"
  type        = map(string)
  default = {
    deviceType  = "sensor_gateway"
    location    = "test_lab"
    syncEnabled = "true"
  }
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}