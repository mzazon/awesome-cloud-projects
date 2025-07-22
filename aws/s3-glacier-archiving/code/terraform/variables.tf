# AWS Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
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

# S3 Bucket Configuration
variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name (random suffix will be added)"
  type        = string
  default     = "long-term-archive"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must start and end with lowercase letters or numbers, and can contain hyphens."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning for additional data protection"
  type        = bool
  default     = true
}

variable "enable_mfa_delete" {
  description = "Enable MFA delete protection (requires bucket versioning)"
  type        = bool
  default     = false
}

# Lifecycle Policy Configuration
variable "archives_transition_days" {
  description = "Number of days before files in 'archives/' prefix transition to Deep Archive"
  type        = number
  default     = 90
  
  validation {
    condition     = var.archives_transition_days >= 1 && var.archives_transition_days <= 365
    error_message = "Archives transition days must be between 1 and 365."
  }
}

variable "general_transition_days" {
  description = "Number of days before all other files transition to Deep Archive"
  type        = number
  default     = 180
  
  validation {
    condition     = var.general_transition_days >= 1 && var.general_transition_days <= 365
    error_message = "General transition days must be between 1 and 365."
  }
}

variable "enable_incomplete_multipart_cleanup" {
  description = "Enable cleanup of incomplete multipart uploads"
  type        = bool
  default     = true
}

variable "incomplete_multipart_cleanup_days" {
  description = "Number of days to retain incomplete multipart uploads"
  type        = number
  default     = 7
  
  validation {
    condition     = var.incomplete_multipart_cleanup_days >= 1 && var.incomplete_multipart_cleanup_days <= 30
    error_message = "Incomplete multipart cleanup days must be between 1 and 30."
  }
}

# Notification Configuration
variable "enable_notifications" {
  description = "Enable SNS notifications for lifecycle transitions"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for archive notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "notification_filter_suffix" {
  description = "File suffix to filter notifications (e.g., '.pdf' for PDF files only)"
  type        = string
  default     = ".pdf"
}

# S3 Inventory Configuration
variable "enable_inventory" {
  description = "Enable S3 inventory reporting for archive tracking"
  type        = bool
  default     = true
}

variable "inventory_frequency" {
  description = "Frequency of inventory reports (Daily or Weekly)"
  type        = string
  default     = "Weekly"
  
  validation {
    condition     = contains(["Daily", "Weekly"], var.inventory_frequency)
    error_message = "Inventory frequency must be either 'Daily' or 'Weekly'."
  }
}

variable "inventory_included_object_versions" {
  description = "Object versions to include in inventory (All or Current)"
  type        = string
  default     = "Current"
  
  validation {
    condition     = contains(["All", "Current"], var.inventory_included_object_versions)
    error_message = "Inventory included object versions must be either 'All' or 'Current'."
  }
}

# Access Control Configuration
variable "enable_public_access_block" {
  description = "Enable public access block settings for enhanced security"
  type        = bool
  default     = true
}

variable "block_public_acls" {
  description = "Block public ACLs on the bucket"
  type        = bool
  default     = true
}

variable "block_public_policy" {
  description = "Block public bucket policies"
  type        = bool
  default     = true
}

variable "ignore_public_acls" {
  description = "Ignore public ACLs on the bucket"
  type        = bool
  default     = true
}

variable "restrict_public_buckets" {
  description = "Restrict public bucket policies"
  type        = bool
  default     = true
}

# Encryption Configuration
variable "enable_server_side_encryption" {
  description = "Enable server-side encryption for the S3 bucket"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for S3 bucket encryption (leave empty to use AWS managed key)"
  type        = string
  default     = ""
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm (AES256 or aws:kms)"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "SSE algorithm must be either 'AES256' or 'aws:kms'."
  }
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}