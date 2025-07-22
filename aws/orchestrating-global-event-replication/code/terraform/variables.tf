# variables.tf - Input variables for multi-region EventBridge replication

# Region Configuration
variable "primary_region" {
  description = "Primary AWS region for EventBridge global endpoint"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for failover"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., us-west-2)."
  }
}

variable "tertiary_region" {
  description = "Tertiary AWS region for additional replication"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.tertiary_region))
    error_message = "Tertiary region must be a valid AWS region format (e.g., eu-west-1)."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "global-events"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# EventBridge Configuration
variable "enable_encryption" {
  description = "Enable KMS encryption for EventBridge event buses"
  type        = bool
  default     = true
}

variable "event_retention_days" {
  description = "Number of days to retain events for replay"
  type        = number
  default     = 7
  
  validation {
    condition = var.event_retention_days >= 1 && var.event_retention_days <= 365
    error_message = "Event retention days must be between 1 and 365."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 128
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Monitoring Configuration
variable "enable_enhanced_monitoring" {
  description = "Enable enhanced CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of periods for alarm evaluation"
  type        = number
  default     = 2
  
  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "alarm_threshold_failures" {
  description = "Threshold for failed invocations alarm"
  type        = number
  default     = 5
  
  validation {
    condition = var.alarm_threshold_failures >= 1
    error_message = "Alarm threshold for failures must be at least 1."
  }
}

variable "alarm_threshold_errors" {
  description = "Threshold for Lambda errors alarm"
  type        = number
  default     = 3
  
  validation {
    condition = var.alarm_threshold_errors >= 1
    error_message = "Alarm threshold for errors must be at least 1."
  }
}

# Route 53 Health Check Configuration
variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = contains([10, 30], var.health_check_interval)
    error_message = "Health check interval must be 10 or 30 seconds."
  }
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive failures before considering endpoint unhealthy"
  type        = number
  default     = 3
  
  validation {
    condition = var.health_check_failure_threshold >= 1 && var.health_check_failure_threshold <= 10
    error_message = "Health check failure threshold must be between 1 and 10."
  }
}

# SNS Configuration
variable "notification_email" {
  description = "Email address for alarm notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Event Pattern Configuration
variable "high_priority_events" {
  description = "List of high priority event sources for cross-region replication"
  type        = list(string)
  default     = ["finance.transactions", "user.management", "system.monitoring"]
  
  validation {
    condition = length(var.high_priority_events) > 0
    error_message = "At least one high priority event source must be specified."
  }
}

variable "financial_amount_threshold" {
  description = "Minimum transaction amount for cross-region replication"
  type        = number
  default     = 1000
  
  validation {
    condition = var.financial_amount_threshold >= 0
    error_message = "Financial amount threshold must be non-negative."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}