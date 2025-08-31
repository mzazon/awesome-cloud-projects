# =============================================================================
# Variable Definitions for Visual Infrastructure Composer Demo
# =============================================================================
# This file defines all configurable parameters for the Terraform configuration
# that creates infrastructure equivalent to what would be designed visually
# using AWS Infrastructure Composer.

# =============================================================================
# Core Infrastructure Variables
# =============================================================================

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name. A random suffix will be appended to ensure uniqueness."
  type        = string
  default     = "my-visual-website"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and identification (e.g., dev, staging, prod)."
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

# =============================================================================
# Website Configuration Variables
# =============================================================================

variable "index_document" {
  description = "The name of the index document for the website (default page served when accessing the root URL)."
  type        = string
  default     = "index.html"
  
  validation {
    condition     = can(regex(".*\\.html?$", var.index_document))
    error_message = "Index document must be an HTML file with .html or .htm extension."
  }
}

variable "error_document" {
  description = "The name of the error document for the website (page served when a 404 error occurs)."
  type        = string
  default     = "error.html"
  
  validation {
    condition     = can(regex(".*\\.html?$", var.error_document))
    error_message = "Error document must be an HTML file with .html or .htm extension."
  }
}

variable "upload_sample_content" {
  description = "Whether to upload sample HTML content to demonstrate the website functionality."
  type        = bool
  default     = true
}

# =============================================================================
# Security and Access Configuration
# =============================================================================

variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket to track changes to website content."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even if it contains objects. Use with caution in production."
  type        = bool
  default     = false
}

# =============================================================================
# Monitoring and Alerting Variables
# =============================================================================

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms for the S3 bucket."
  type        = bool
  default     = false
}

variable "bucket_size_threshold" {
  description = "CloudWatch alarm threshold for bucket size in bytes. Alarm triggers when bucket size exceeds this value."
  type        = number
  default     = 1073741824 # 1 GB in bytes
  
  validation {
    condition     = var.bucket_size_threshold > 0
    error_message = "Bucket size threshold must be a positive number."
  }
}

variable "object_count_threshold" {
  description = "CloudWatch alarm threshold for number of objects. Alarm triggers when object count exceeds this value."
  type        = number
  default     = 1000
  
  validation {
    condition     = var.object_count_threshold > 0
    error_message = "Object count threshold must be a positive number."
  }
}

variable "sns_topic_arn" {
  description = "ARN of SNS topic for CloudWatch alarm notifications. Leave empty to disable notifications."
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_topic_arn == "" || can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9-_]+$", var.sns_topic_arn))
    error_message = "SNS topic ARN must be empty or a valid ARN format."
  }
}

# =============================================================================
# Advanced Configuration Variables
# =============================================================================

variable "cors_rules" {
  description = "CORS rules for the S3 bucket to enable cross-origin requests."
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = list(string)
    max_age_seconds = number
  }))
  default = []
}

variable "lifecycle_rules" {
  description = "Lifecycle rules to manage object transitions and expiration."
  type = list(object({
    id                          = string
    enabled                     = bool
    prefix                      = string
    expiration_days            = number
    noncurrent_version_expiration_days = number
  }))
  default = []
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9+\\-=._:/@]+$", k))])
    error_message = "Tag keys must contain only alphanumeric characters and the following special characters: + - = . _ : / @"
  }
}

# =============================================================================
# Regional Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created. If not specified, the provider's default region is used."
  type        = string
  default     = null
  
  validation {
    condition = var.aws_region == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

# =============================================================================
# Content Security Configuration
# =============================================================================

variable "content_security_policy" {
  description = "Content Security Policy header value for enhanced security."
  type        = string
  default     = "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'"
}

variable "enable_https_redirect" {
  description = "Enable automatic redirect from HTTP to HTTPS (requires CloudFront)."
  type        = bool
  default     = false
}

# =============================================================================
# Backup and Recovery Configuration
# =============================================================================

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery."
  type        = bool
  default     = false
}

variable "replication_destination_bucket" {
  description = "Destination bucket ARN for cross-region replication."
  type        = string
  default     = ""
  
  validation {
    condition = var.replication_destination_bucket == "" || can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9-]*[a-z0-9]$", var.replication_destination_bucket))
    error_message = "Replication destination bucket must be empty or a valid S3 bucket ARN."
  }
}