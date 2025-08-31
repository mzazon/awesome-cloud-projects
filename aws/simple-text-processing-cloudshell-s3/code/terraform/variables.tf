# Input variables for the text processing infrastructure
# These variables allow customization of the deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name (will be appended with random suffix for uniqueness)"
  type        = string
  default     = "text-processing-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must start and end with a lowercase letter or number and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for data protection"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "lifecycle_transition_days" {
  description = "Number of days after which objects transition to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_transition_days >= 30
    error_message = "Lifecycle transition days must be at least 30 days for IA storage class."
  }
}

variable "lifecycle_expiration_days" {
  description = "Number of days after which objects are deleted (0 to disable)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.lifecycle_expiration_days >= 0
    error_message = "Lifecycle expiration days must be a positive number or 0 to disable."
  }
}

variable "allowed_principals" {
  description = "List of AWS principals (users/roles) allowed to access the S3 bucket"
  type        = list(string)
  default     = []
}

variable "create_sample_data" {
  description = "Whether to create and upload sample sales data for testing"
  type        = bool
  default     = true
}

variable "folder_structure" {
  description = "Folder structure to create in the S3 bucket"
  type        = list(string)
  default     = ["input/", "output/", "archive/", "temp/"]
}

variable "notification_email" {
  description = "Email address for S3 event notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for S3 API calls"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_tags : 
      can(regex("^[a-zA-Z0-9_\\-]+$", key)) && length(key) <= 128 && length(value) <= 256
    ])
    error_message = "Tag keys must contain only alphanumeric characters, underscores, and hyphens, be no longer than 128 characters. Tag values must be no longer than 256 characters."
  }
}