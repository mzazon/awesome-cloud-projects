# Core configuration variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project for cost estimation tracking"
  type        = string
  default     = "web-app-migration"
  
  validation {
    condition     = length(var.project_name) > 3 && length(var.project_name) <= 50
    error_message = "Project name must be between 3 and 50 characters."
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

# S3 bucket configuration
variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name (random suffix will be added)"
  type        = string
  default     = "cost-estimates"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix)) && length(var.bucket_name_prefix) <= 20
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens, and be 20 characters or less."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for estimate history tracking"
  type        = bool
  default     = true
}

variable "enable_lifecycle_policy" {
  description = "Enable S3 lifecycle policy for cost optimization"
  type        = bool
  default     = true
}

# Lifecycle policy configuration
variable "transition_to_ia_days" {
  description = "Number of days before transitioning objects to Standard-IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "transition_to_glacier_days" {
  description = "Number of days before transitioning objects to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.transition_to_glacier_days >= 30
    error_message = "Transition to Glacier must be at least 30 days."
  }
}

variable "transition_to_deep_archive_days" {
  description = "Number of days before transitioning objects to Deep Archive storage class"
  type        = number
  default     = 365
  
  validation {
    condition     = var.transition_to_deep_archive_days >= 90
    error_message = "Transition to Deep Archive must be at least 90 days."
  }
}

# Budget configuration
variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD for cost monitoring"
  type        = number
  default     = 50.00
  
  validation {
    condition     = var.monthly_budget_amount > 0 && var.monthly_budget_amount <= 10000
    error_message = "Monthly budget amount must be between $0 and $10,000."
  }
}

variable "budget_alert_threshold" {
  description = "Budget alert threshold percentage (e.g., 80 for 80%)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.budget_alert_threshold >= 50 && var.budget_alert_threshold <= 100
    error_message = "Budget alert threshold must be between 50 and 100 percent."
  }
}

variable "notification_email" {
  description = "Email address for budget notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Folder structure configuration
variable "estimate_folders" {
  description = "List of folder paths to create in the S3 bucket for organizing estimates"
  type        = list(string)
  default = [
    "estimates/2025/Q1/",
    "estimates/2025/Q2/",
    "estimates/2025/Q3/",
    "estimates/2025/Q4/",
    "archived/"
  ]
}

# Tagging configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}