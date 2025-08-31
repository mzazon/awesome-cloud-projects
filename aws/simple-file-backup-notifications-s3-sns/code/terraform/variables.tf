# Input variables for the Simple File Backup Notifications infrastructure
# These variables allow customization of the deployment for different environments

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "backup-notifications"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "email_addresses" {
  description = "List of email addresses to receive backup notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    condition = length(var.email_addresses) > 0
    error_message = "At least one valid email address must be provided."
  }
}

variable "s3_bucket_prefix" {
  description = "Prefix for the S3 bucket name (will be combined with random suffix)"
  type        = string
  default     = "backup-notifications"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "sns_topic_name" {
  description = "Name for the SNS topic (will be combined with random suffix)"
  type        = string
  default     = "backup-alerts"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.sns_topic_name))
    error_message = "SNS topic name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket for data protection"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable server-side encryption on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_encryption_algorithm" {
  description = "Server-side encryption algorithm for S3 bucket"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "S3 encryption algorithm must be either AES256 or aws:kms."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days after which backup files will be automatically deleted (0 = disabled)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.s3_lifecycle_expiration_days >= 0
    error_message = "Lifecycle expiration days must be 0 or greater."
  }
}

variable "notification_event_types" {
  description = "List of S3 event types that will trigger notifications"
  type        = list(string)
  default     = ["s3:ObjectCreated:*"]
  
  validation {
    condition = alltrue([
      for event in var.notification_event_types : can(regex("^s3:", event))
    ])
    error_message = "All event types must be valid S3 event types starting with 's3:'."
  }
}

variable "s3_object_prefix_filter" {
  description = "Optional prefix filter for S3 notifications (empty string = all objects)"
  type        = string
  default     = ""
}

variable "s3_object_suffix_filter" {
  description = "Optional suffix filter for S3 notifications (empty string = all objects)"
  type        = string
  default     = ""
}

variable "sns_display_name" {
  description = "Display name for the SNS topic"
  type        = string
  default     = "Backup File Notifications"
}

variable "enable_cloudtrail_logging" {
  description = "Enable CloudTrail logging for S3 bucket access (additional costs apply)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.tags : can(regex("^[a-zA-Z0-9\\s._:/=+@-]*$", key)) && can(regex("^[a-zA-Z0-9\\s._:/=+@-]*$", value))
    ])
    error_message = "Tag keys and values must contain only valid characters."
  }
}