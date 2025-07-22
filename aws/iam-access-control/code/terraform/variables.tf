# Input Variables for Fine-Grained Access Control with IAM Policies and Conditions
# This file defines all configurable parameters for the Terraform deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name prefix for all resources created by this configuration"
  type        = string
  default     = "finegrained-access"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 20
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens, and be 20 characters or less."
  }
}

variable "environment" {
  description = "Environment tag for resources (dev, test, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "business_hours_start" {
  description = "Start time for business hours access in UTC (24-hour format, e.g., '09:00')"
  type        = string
  default     = "09:00"

  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.business_hours_start))
    error_message = "Business hours start time must be in HH:MM format (24-hour)."
  }
}

variable "business_hours_end" {
  description = "End time for business hours access in UTC (24-hour format, e.g., '17:00')"
  type        = string
  default     = "17:00"

  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.business_hours_end))
    error_message = "Business hours end time must be in HH:MM format (24-hour)."
  }
}

variable "allowed_ip_ranges" {
  description = "List of IP CIDR blocks allowed to access resources"
  type        = list(string)
  default     = ["203.0.113.0/24", "198.51.100.0/24"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

variable "test_department" {
  description = "Department tag value for testing tag-based access control"
  type        = string
  default     = "Engineering"

  validation {
    condition     = can(regex("^[A-Za-z]+$", var.test_department))
    error_message = "Department must contain only letters."
  }
}

variable "mfa_max_age_seconds" {
  description = "Maximum age of MFA authentication in seconds for sensitive operations"
  type        = number
  default     = 3600

  validation {
    condition     = var.mfa_max_age_seconds > 0 && var.mfa_max_age_seconds <= 43200
    error_message = "MFA max age must be between 1 and 43200 seconds (12 hours)."
  }
}

variable "session_duration_seconds" {
  description = "Maximum session duration in seconds for temporary credentials"
  type        = number
  default     = 3600

  validation {
    condition     = var.session_duration_seconds >= 900 && var.session_duration_seconds <= 43200
    error_message = "Session duration must be between 900 (15 minutes) and 43200 seconds (12 hours)."
  }
}

variable "s3_encryption_type" {
  description = "Server-side encryption type for S3 objects"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_type)
    error_message = "S3 encryption type must be either 'AES256' or 'aws:kms'."
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for API calls audit"
  type        = bool
  default     = true
}

variable "create_test_resources" {
  description = "Create test users, roles, and sample data for validation"
  type        = bool
  default     = true
}

variable "resource_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.resource_tags : can(regex("^[A-Za-z0-9\\s\\._:/=+\\-@]+$", key)) && can(regex("^[A-Za-z0-9\\s\\._:/=+\\-@]*$", value))
    ])
    error_message = "Tag keys and values must contain only alphanumeric characters, spaces, and the characters ._:/=+-@."
  }
}