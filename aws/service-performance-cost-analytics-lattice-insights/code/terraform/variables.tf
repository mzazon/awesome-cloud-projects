# AWS Region
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

# Environment
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# Resource naming prefix
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "lattice-analytics"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.name_prefix))
    error_message = "Name prefix must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

# CloudWatch Log Group retention
variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention period."
  }
}

# Lambda function configuration
variable "lambda_timeout_seconds" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 180
  
  validation {
    condition     = var.lambda_timeout_seconds >= 1 && var.lambda_timeout_seconds <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_mb" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

# EventBridge schedule expression
variable "analytics_schedule" {
  description = "Schedule expression for analytics pipeline (rate or cron)"
  type        = string
  default     = "rate(6 hours)"
  
  validation {
    condition     = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.analytics_schedule))
    error_message = "Schedule must be a valid rate or cron expression."
  }
}

# Cost anomaly detection threshold
variable "cost_anomaly_threshold" {
  description = "Threshold percentage for cost anomaly detection"
  type        = number
  default     = 50.0
  
  validation {
    condition     = var.cost_anomaly_threshold >= 0 && var.cost_anomaly_threshold <= 100
    error_message = "Cost anomaly threshold must be between 0 and 100."
  }
}

# Notification email for cost anomalies
variable "notification_email" {
  description = "Email address for cost anomaly notifications"
  type        = string
  default     = "admin@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

# VPC Lattice service network configuration
variable "service_network_auth_type" {
  description = "Authentication type for VPC Lattice service network"
  type        = string
  default     = "AWS_IAM"
  
  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.service_network_auth_type)
    error_message = "Auth type must be NONE or AWS_IAM."
  }
}

# Enable/disable cost anomaly detection
variable "enable_cost_anomaly_detection" {
  description = "Whether to enable cost anomaly detection"
  type        = bool
  default     = true
}

# Enable/disable CloudWatch dashboard
variable "enable_dashboard" {
  description = "Whether to create CloudWatch dashboard"
  type        = bool
  default     = true
}

# Sample service configuration
variable "create_sample_service" {
  description = "Whether to create a sample VPC Lattice service for testing"
  type        = bool
  default     = true
}

# Tags for all resources
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}