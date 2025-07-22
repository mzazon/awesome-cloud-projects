# Project configuration variables
variable "project_name" {
  description = "Name of the carbon footprint optimization project"
  type        = string
  default     = "carbon-optimizer"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Notification configuration
variable "notification_email" {
  description = "Email address for carbon optimization notifications"
  type        = string
  default     = ""
  
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

# Lambda configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# DynamoDB configuration
variable "dynamodb_read_capacity" {
  description = "DynamoDB table read capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_read_capacity >= 1
    error_message = "DynamoDB read capacity must be at least 1."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB table write capacity units"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dynamodb_write_capacity >= 1
    error_message = "DynamoDB write capacity must be at least 1."
  }
}

# Schedule configuration
variable "monthly_analysis_schedule" {
  description = "Schedule expression for monthly carbon footprint analysis"
  type        = string
  default     = "rate(30 days)"
  
  validation {
    condition     = can(regex("^(rate\\(\\d+\\s+(minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.monthly_analysis_schedule))
    error_message = "Must be a valid EventBridge schedule expression."
  }
}

variable "weekly_analysis_schedule" {
  description = "Schedule expression for weekly carbon footprint trend analysis"
  type        = string
  default     = "rate(7 days)"
  
  validation {
    condition     = can(regex("^(rate\\(\\d+\\s+(minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.weekly_analysis_schedule))
    error_message = "Must be a valid EventBridge schedule expression."
  }
}

# Cost and Usage Report configuration
variable "enable_cur_integration" {
  description = "Enable Cost and Usage Report integration for enhanced analysis"
  type        = bool
  default     = true
}

variable "cur_report_name" {
  description = "Name for the Cost and Usage Report"
  type        = string
  default     = "carbon-optimization-detailed-report"
}

# S3 configuration
variable "s3_force_destroy" {
  description = "Force destroy S3 bucket even if it contains objects (for development/testing)"
  type        = bool
  default     = false
}

# Sustainability Scanner configuration
variable "enable_sustainability_scanner" {
  description = "Enable Sustainability Scanner integration"
  type        = bool
  default     = true
}

variable "scanner_severity_threshold" {
  description = "Minimum severity level for Sustainability Scanner alerts"
  type        = string
  default     = "medium"
  
  validation {
    condition     = contains(["low", "medium", "high", "critical"], var.scanner_severity_threshold)
    error_message = "Scanner severity threshold must be one of: low, medium, high, critical."
  }
}

# Carbon analysis configuration
variable "carbon_optimization_threshold" {
  description = "Carbon intensity threshold for triggering optimization recommendations (kg CO2e per USD)"
  type        = number
  default     = 0.5
  
  validation {
    condition     = var.carbon_optimization_threshold > 0
    error_message = "Carbon optimization threshold must be greater than 0."
  }
}

variable "high_impact_cost_threshold" {
  description = "Monthly cost threshold (USD) for identifying high-impact optimization opportunities"
  type        = number
  default     = 100
  
  validation {
    condition     = var.high_impact_cost_threshold > 0
    error_message = "High impact cost threshold must be greater than 0."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}