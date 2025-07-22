# Variables for Operational Analytics with CloudWatch Insights
# This file defines all configurable parameters for the infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "operational-analytics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention value."
  }
}

variable "error_rate_threshold" {
  description = "Error rate threshold for CloudWatch alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.error_rate_threshold > 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 1 and 100."
  }
}

variable "log_volume_threshold" {
  description = "Log volume threshold for cost monitoring (events per hour)"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.log_volume_threshold > 0
    error_message = "Log volume threshold must be greater than 0."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

variable "notification_email" {
  description = "Email address for operational alerts (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex(
      "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", 
      var.notification_email
    ))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = ""
  
  validation {
    condition     = var.dashboard_name == "" || can(regex("^[a-zA-Z0-9_-]+$", var.dashboard_name))
    error_message = "Dashboard name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "enable_anomaly_detection" {
  description = "Enable CloudWatch anomaly detection for log ingestion patterns"
  type        = bool
  default     = true
}

variable "anomaly_detection_threshold" {
  description = "Anomaly detection threshold (standard deviations)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.anomaly_detection_threshold >= 1 && var.anomaly_detection_threshold <= 5
    error_message = "Anomaly detection threshold must be between 1 and 5 standard deviations."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 128
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}