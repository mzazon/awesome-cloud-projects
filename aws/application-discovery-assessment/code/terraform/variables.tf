# Variables for Application Discovery Service Infrastructure
# This file defines all configurable parameters for the deployment

# Required Variables
variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format: us-west-2, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Migration Hub Configuration
variable "migration_hub_home_region" {
  description = "AWS region to use as Migration Hub home region"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.migration_hub_home_region))
    error_message = "Migration Hub home region must be a valid AWS region."
  }
}

# S3 Configuration
variable "discovery_bucket_name" {
  description = "Name for S3 bucket to store discovery data (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_days" {
  description = "Number of days to retain discovery data in S3"
  type        = number
  default     = 90
  
  validation {
    condition = var.bucket_lifecycle_days >= 30 && var.bucket_lifecycle_days <= 365
    error_message = "Bucket lifecycle days must be between 30 and 365."
  }
}

# Application Discovery Service Configuration
variable "enable_continuous_export" {
  description = "Enable continuous export of discovery data to S3"
  type        = bool
  default     = true
}

variable "discovery_export_format" {
  description = "Format for discovery data export"
  type        = string
  default     = "CSV"
  
  validation {
    condition = contains(["CSV"], var.discovery_export_format)
    error_message = "Export format must be CSV."
  }
}

# Application Groups Configuration
variable "application_groups" {
  description = "List of application groups to create"
  type = list(object({
    name        = string
    description = string
  }))
  default = [
    {
      name        = "WebApplication"
      description = "Web application servers discovered during assessment"
    },
    {
      name        = "DatabaseServers"
      description = "Database servers discovered during assessment"
    }
  ]
}

# CloudWatch Events Configuration
variable "enable_automated_reports" {
  description = "Enable automated weekly discovery reports"
  type        = bool
  default     = true
}

variable "report_schedule" {
  description = "Schedule expression for automated reports (CloudWatch Events format)"
  type        = string
  default     = "rate(7 days)"
}

# Lambda Configuration
variable "lambda_timeout" {
  description = "Timeout for Lambda functions (in seconds)"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory" {
  description = "Memory allocation for Lambda functions (in MB)"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory >= 128 && var.lambda_memory <= 3008
    error_message = "Lambda memory must be between 128 and 3008 MB."
  }
}

# Athena Configuration
variable "enable_athena_analysis" {
  description = "Enable Athena for discovery data analysis"
  type        = bool
  default     = true
}

variable "athena_database_name" {
  description = "Name for Athena database"
  type        = string
  default     = "discovery_analysis"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9_]*$", var.athena_database_name))
    error_message = "Athena database name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

# Notification Configuration
variable "enable_sns_notifications" {
  description = "Enable SNS notifications for discovery events"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for notifications (required if SNS is enabled)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "ads"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only letters, numbers, and hyphens."
  }
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for S3 bucket and other resources"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to wait before deleting KMS key"
  type        = number
  default     = 7
  
  validation {
    condition = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Tags Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}