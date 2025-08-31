# Variables for Simple Infrastructure Templates with CloudFormation and S3
# This file defines all input variables for the Terraform configuration

# Core Configuration Variables
variable "bucket_name_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be appended for uniqueness."
  type        = string
  default     = "my-infrastructure-bucket"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix)) && length(var.bucket_name_prefix) >= 3 && length(var.bucket_name_prefix) <= 50
    error_message = "Bucket name prefix must be 3-50 characters, start and end with lowercase letters or numbers, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and identification (e.g., dev, staging, prod)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production", "dev", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: development, staging, production, dev, stage, prod."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created. If not specified, uses provider default."
  type        = string
  default     = null
}

# S3 Configuration Variables
variable "enable_versioning" {
  description = "Enable versioning for the S3 bucket to protect against accidental deletion or modification"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption for the S3 bucket using AES256"
  type        = bool
  default     = true
}

variable "encryption_algorithm" {
  description = "Server-side encryption algorithm to use for S3 bucket encryption"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "Encryption algorithm must be either 'AES256' (S3 managed) or 'aws:kms' (KMS managed)."
  }
}

variable "kms_key_id" {
  description = "KMS key ID for S3 bucket encryption. Only used when encryption_algorithm is 'aws:kms'. If not specified, uses AWS managed KMS key."
  type        = string
  default     = null
}

variable "enable_bucket_key" {
  description = "Enable S3 Bucket Key to reduce KMS costs by reducing calls to AWS KMS"
  type        = bool
  default     = true
}

variable "block_public_access" {
  description = "Enable all public access blocks for enhanced security"
  type        = object({
    block_public_acls       = bool
    block_public_policy     = bool
    ignore_public_acls      = bool
    restrict_public_buckets = bool
  })
  default = {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

# Lifecycle Management Variables
variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policy for automatic object transition and expiration"
  type        = bool
  default     = false
}

variable "lifecycle_transition_ia_days" {
  description = "Number of days after object creation to transition to Standard-IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_transition_ia_days >= 30
    error_message = "Standard-IA transition must be at least 30 days."
  }
}

variable "lifecycle_transition_glacier_days" {
  description = "Number of days after object creation to transition to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.lifecycle_transition_glacier_days >= 90
    error_message = "Glacier transition must be at least 90 days."
  }
}

variable "lifecycle_expiration_days" {
  description = "Number of days after object creation to expire (delete) objects. Set to 0 to disable expiration."
  type        = number
  default     = 0
  
  validation {
    condition     = var.lifecycle_expiration_days >= 0
    error_message = "Expiration days must be non-negative. Use 0 to disable expiration."
  }
}

# Monitoring and Logging Variables
variable "enable_access_logging" {
  description = "Enable S3 access logging to track requests made to the bucket"
  type        = bool
  default     = false
}

variable "access_log_bucket_name" {
  description = "Name of the S3 bucket to store access logs. If not specified and access logging is enabled, a separate log bucket will be created."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  description = "Prefix for S3 access log objects"
  type        = string
  default     = "access-logs/"
}

# Tagging Variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources beyond the default tags"
  type        = map(string)
  default     = {}
}

variable "bucket_specific_tags" {
  description = "Additional tags specific to the S3 bucket"
  type        = map(string)
  default = {
    Purpose = "Infrastructure-Template-Demo"
  }
}

# Advanced Configuration Variables
variable "mfa_delete" {
  description = "Enable MFA delete for the S3 bucket. Can only be enabled via root account."
  type        = bool
  default     = false
}

variable "request_payer" {
  description = "Specifies who pays for the download and request fees (BucketOwner or Requester)"  
  type        = string
  default     = "BucketOwner"
  
  validation {
    condition     = contains(["BucketOwner", "Requester"], var.request_payer)
    error_message = "Request payer must be either 'BucketOwner' or 'Requester'."
  }
}

variable "object_lock_enabled" {
  description = "Enable S3 Object Lock for WORM (Write Once Read Many) compliance"
  type        = bool
  default     = false
}

variable "object_lock_configuration" {
  description = "S3 Object Lock configuration for WORM compliance"
  type = object({
    object_lock_enabled = bool
    rule = optional(object({
      default_retention = object({
        mode  = string # "GOVERNANCE" or "COMPLIANCE"
        days  = optional(number)
        years = optional(number)
      })
    }))
  })
  default = {
    object_lock_enabled = false
    rule                = null
  }
}