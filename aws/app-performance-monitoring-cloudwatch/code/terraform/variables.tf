# =============================================================================
# Variables for Automated Application Performance Monitoring Infrastructure
# 
# This file defines all input variables for the Terraform configuration,
# providing flexibility and customization options for different environments
# and use cases.
# =============================================================================

# =============================================================================
# Project and Environment Configuration
# =============================================================================

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "app-performance-monitoring"
  
  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 50
    error_message = "Project name must be between 3 and 50 characters long."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod) used for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = null # Uses provider default region
  
  validation {
    condition = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

# =============================================================================
# Application Configuration
# =============================================================================

variable "application_services" {
  description = "List of application services to monitor with CloudWatch Application Signals"
  type        = list(string)
  default     = ["MyApplication", "WebService", "APIService"]
  
  validation {
    condition     = length(var.application_services) > 0 && length(var.application_services) <= 20
    error_message = "At least one service must be specified and maximum 20 services are allowed."
  }
  
  validation {
    condition = alltrue([
      for service in var.application_services : 
      can(regex("^[a-zA-Z0-9_-]+$", service)) && length(service) >= 3 && length(service) <= 255
    ])
    error_message = "Service names must be 3-255 characters and contain only alphanumeric characters, hyphens, and underscores."
  }
}

# =============================================================================
# Notification Configuration
# =============================================================================

variable "notification_email" {
  description = "Email address to receive performance alerts (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# =============================================================================
# CloudWatch Alarm Configuration
# =============================================================================

variable "alarm_period" {
  description = "The period in seconds over which the alarm statistic is applied"
  type        = number
  default     = 300
  
  validation {
    condition     = contains([60, 300, 600, 900, 3600], var.alarm_period)
    error_message = "Alarm period must be one of: 60, 300, 600, 900, 3600 seconds."
  }
}

# Latency alarm configuration
variable "latency_threshold_ms" {
  description = "Latency threshold in milliseconds for triggering alarms"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.latency_threshold_ms > 0 && var.latency_threshold_ms <= 60000
    error_message = "Latency threshold must be between 1 and 60000 milliseconds."
  }
}

variable "latency_evaluation_periods" {
  description = "Number of evaluation periods for latency alarm"
  type        = number
  default     = 2
  
  validation {
    condition     = var.latency_evaluation_periods >= 1 && var.latency_evaluation_periods <= 10
    error_message = "Latency evaluation periods must be between 1 and 10."
  }
}

# Error rate alarm configuration
variable "error_rate_threshold_percent" {
  description = "Error rate threshold in percentage for triggering alarms"
  type        = number
  default     = 5.0
  
  validation {
    condition     = var.error_rate_threshold_percent >= 0 && var.error_rate_threshold_percent <= 100
    error_message = "Error rate threshold must be between 0 and 100 percent."
  }
}

variable "error_rate_evaluation_periods" {
  description = "Number of evaluation periods for error rate alarm"
  type        = number
  default     = 1
  
  validation {
    condition     = var.error_rate_evaluation_periods >= 1 && var.error_rate_evaluation_periods <= 10
    error_message = "Error rate evaluation periods must be between 1 and 10."
  }
}

# Throughput alarm configuration
variable "throughput_threshold_requests" {
  description = "Minimum number of requests per period to avoid low throughput alarm"
  type        = number
  default     = 10
  
  validation {
    condition     = var.throughput_threshold_requests >= 1
    error_message = "Throughput threshold must be at least 1 request."
  }
}

variable "throughput_evaluation_periods" {
  description = "Number of evaluation periods for throughput alarm"
  type        = number
  default     = 3
  
  validation {
    condition     = var.throughput_evaluation_periods >= 1 && var.throughput_evaluation_periods <= 10
    error_message = "Throughput evaluation periods must be between 1 and 10."
  }
}

# =============================================================================
# Lambda Function Configuration
# =============================================================================

variable "lambda_log_level" {
  description = "Log level for Lambda function (DEBUG, INFO, WARNING, ERROR)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.lambda_log_level)
    error_message = "Lambda log level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}

variable "lambda_log_retention_days" {
  description = "Number of days to retain Lambda function logs in CloudWatch"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.lambda_log_retention_days)
    error_message = "Lambda log retention days must be a valid CloudWatch log retention period."
  }
}

# =============================================================================
# CloudWatch Application Signals Configuration
# =============================================================================

variable "application_signals_log_retention_days" {
  description = "Number of days to retain Application Signals logs in CloudWatch"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.application_signals_log_retention_days)
    error_message = "Application Signals log retention days must be a valid CloudWatch log retention period."
  }
}

# =============================================================================
# Auto Scaling Configuration (Optional)
# =============================================================================

variable "enable_auto_scaling" {
  description = "Enable automatic scaling responses to performance alerts"
  type        = bool
  default     = false
}

variable "auto_scaling_group_names" {
  description = "List of Auto Scaling Group names that can be scaled by the Lambda function"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for asg_name in var.auto_scaling_group_names : 
      can(regex("^[a-zA-Z0-9\\-._/]+$", asg_name)) && length(asg_name) <= 255
    ])
    error_message = "Auto Scaling Group names must be valid AWS resource names."
  }
}

variable "scaling_cooldown_minutes" {
  description = "Cooldown period in minutes before allowing another scaling action"
  type        = number
  default     = 5
  
  validation {
    condition     = var.scaling_cooldown_minutes >= 1 && var.scaling_cooldown_minutes <= 60
    error_message = "Scaling cooldown must be between 1 and 60 minutes."
  }
}

# =============================================================================
# Dashboard Configuration
# =============================================================================

variable "enable_dashboard" {
  description = "Enable CloudWatch dashboard creation for performance monitoring"
  type        = bool
  default     = true
}

variable "dashboard_refresh_interval" {
  description = "Dashboard refresh interval in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = contains([60, 300, 900, 1800, 3600], var.dashboard_refresh_interval)
    error_message = "Dashboard refresh interval must be one of: 60, 300, 900, 1800, 3600 seconds."
  }
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for CloudWatch Logs"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting CloudWatch Logs (uses default service key if not specified)"
  type        = string
  default     = null
  
  validation {
    condition = var.kms_key_id == null || can(regex("^(arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+|alias/[a-zA-Z0-9/_-]+|[a-f0-9-]{36})$", var.kms_key_id))
    error_message = "KMS key ID must be a valid ARN, alias, or key ID format."
  }
}

# =============================================================================
# Cost Optimization Configuration
# =============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features like scheduled scaling and resource tagging"
  type        = bool
  default     = true
}

variable "cost_allocation_tags" {
  description = "Additional tags for cost allocation and tracking"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.cost_allocation_tags : 
      length(key) <= 128 && length(value) <= 256
    ])
    error_message = "Tag keys must be 128 characters or less, and values must be 256 characters or less."
  }
}

# =============================================================================
# Advanced Configuration
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : 
      length(key) <= 128 && length(value) <= 256 &&
      !contains(["aws:", "AWS:"], substr(key, 0, 4))
    ])
    error_message = "Tag keys must be 128 characters or less, values must be 256 characters or less, and keys cannot start with 'aws:' or 'AWS:'."
  }
}

variable "create_service_linked_role" {
  description = "Create service-linked role for Application Signals (required for first-time setup)"
  type        = bool
  default     = false
}

variable "custom_lambda_code_path" {
  description = "Path to custom Lambda function code (overrides default implementation)"
  type        = string
  default     = null
  
  validation {
    condition = var.custom_lambda_code_path == null || can(fileexists(var.custom_lambda_code_path))
    error_message = "Custom Lambda code path must point to an existing file."
  }
}