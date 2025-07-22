# Variables for AWS Transfer Family Web Apps self-service file management infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "file-management"
}

variable "bucket_name_suffix" {
  description = "Optional suffix for S3 bucket name (random suffix will be added automatically)"
  type        = string
  default     = ""
}

variable "create_test_user" {
  description = "Whether to create a test user in IAM Identity Center"
  type        = bool
  default     = true
}

variable "test_user_email" {
  description = "Email address for the test user"
  type        = string
  default     = "testuser@example.com"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.test_user_email))
    error_message = "Test user email must be a valid email address."
  }
}

variable "webapp_branding" {
  description = "Branding configuration for the Transfer Family Web App"
  type = object({
    title       = string
    description = string
    logo_url    = optional(string)
    favicon_url = optional(string)
  })
  default = {
    title       = "Secure File Management Portal"
    description = "Upload, download, and manage your files securely"
    logo_url    = "https://via.placeholder.com/200x60/0066CC/FFFFFF?text=Your+Logo"
    favicon_url = "https://via.placeholder.com/32x32/0066CC/FFFFFF?text=F"
  }
}

variable "s3_versioning_enabled" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable lifecycle policies on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning objects to IA storage class"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_lifecycle_transition_days >= 30
    error_message = "Lifecycle transition days must be at least 30."
  }
}

variable "access_grants_location_scope" {
  description = "S3 location scope for access grants (relative to bucket)"
  type        = string
  default     = "user-files/*"
}

variable "access_grants_permission" {
  description = "Permission level for access grants"
  type        = string
  default     = "READWRITE"

  validation {
    condition     = contains(["READ", "READWRITE", "WRITE"], var.access_grants_permission)
    error_message = "Access grants permission must be one of: READ, READWRITE, WRITE."
  }
}

variable "use_default_vpc" {
  description = "Whether to use the default VPC for the Transfer Family Web App"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID to use if not using default VPC (only used when use_default_vpc is false)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs to use if not using default VPC (only used when use_default_vpc is false)"
  type        = list(string)
  default     = []
}

variable "create_sample_files" {
  description = "Whether to create sample files in the S3 bucket"
  type        = bool
  default     = true
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for S3 API calls"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}