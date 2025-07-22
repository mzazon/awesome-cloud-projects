# ==========================================================================
# TERRAFORM VARIABLES - AWS Transfer Family Web App File Portal
# ==========================================================================
# This file defines all configurable parameters for the secure file portal
# deployment, including environment settings, user configuration, and
# optional features like backup and monitoring.

# ==========================================================================
# GENERAL CONFIGURATION
# ==========================================================================

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "secure-file-portal"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, test, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "cost_center" {
  description = "Cost center for billing and cost allocation"
  type        = string
  default     = "IT-Operations"
}

# ==========================================================================
# TRANSFER FAMILY WEB APP CONFIGURATION
# ==========================================================================

variable "web_app_units" {
  description = "Number of web app units for the Transfer Family Web App (affects pricing and performance)"
  type        = number
  default     = 1
  
  validation {
    condition     = var.web_app_units >= 1 && var.web_app_units <= 10
    error_message = "Web app units must be between 1 and 10."
  }
}

# ==========================================================================
# IAM IDENTITY CENTER USER CONFIGURATION
# ==========================================================================

variable "create_identity_center_user" {
  description = "Whether to create a test user in IAM Identity Center for demonstration purposes"
  type        = bool
  default     = true
}

variable "test_user_name" {
  description = "Username for the test IAM Identity Center user"
  type        = string
  default     = "portal-test-user"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.test_user_name))
    error_message = "Username must contain only alphanumeric characters, periods, hyphens, and underscores."
  }
}

variable "test_user_display_name" {
  description = "Display name for the test IAM Identity Center user"
  type        = string
  default     = "Portal Test User"
}

variable "test_user_given_name" {
  description = "Given (first) name for the test IAM Identity Center user"
  type        = string
  default     = "Portal"
}

variable "test_user_family_name" {
  description = "Family (last) name for the test IAM Identity Center user"
  type        = string
  default     = "User"
}

variable "test_user_email" {
  description = "Email address for the test IAM Identity Center user"
  type        = string
  default     = "portal-test@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.test_user_email))
    error_message = "Must be a valid email address."
  }
}

# ==========================================================================
# S3 BUCKET CONFIGURATION
# ==========================================================================

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket for file history"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle policies for cost optimization"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Number of days after which to transition objects to Infrequent Access storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_transition_to_ia_days >= 0
    error_message = "Transition days must be a positive number."
  }
}

variable "s3_transition_to_glacier_days" {
  description = "Number of days after which to transition objects to Glacier storage class"
  type        = number
  default     = 60
  
  validation {
    condition     = var.s3_transition_to_glacier_days >= 0
    error_message = "Transition days must be a positive number."
  }
}

variable "s3_expiration_days" {
  description = "Number of days after which to delete non-current object versions"
  type        = number
  default     = 365
  
  validation {
    condition     = var.s3_expiration_days >= 0
    error_message = "Expiration days must be a positive number."
  }
}

# ==========================================================================
# SECURITY AND COMPLIANCE CONFIGURATION
# ==========================================================================

variable "enable_access_logging" {
  description = "Enable S3 access logging for compliance and audit"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption for S3 bucket"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of KMS key for S3 encryption (optional - uses AES256 if not provided)"
  type        = string
  default     = null
}

variable "enable_public_access_block" {
  description = "Enable public access block settings for S3 bucket security"
  type        = bool
  default     = true
}

# ==========================================================================
# MONITORING AND LOGGING CONFIGURATION
# ==========================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_security_monitoring" {
  description = "Enable CloudWatch alarms for security events"
  type        = bool
  default     = true
}

variable "failed_login_threshold" {
  description = "Number of failed login attempts before triggering alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.failed_login_threshold >= 1
    error_message = "Failed login threshold must be at least 1."
  }
}

variable "sns_topic_arn" {
  description = "ARN of SNS topic for security alerts (optional)"
  type        = string
  default     = null
}

# ==========================================================================
# BACKUP CONFIGURATION
# ==========================================================================

variable "enable_backup" {
  description = "Enable AWS Backup for S3 bucket"
  type        = bool
  default     = false
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule (default: daily at 5 AM UTC)"
  type        = string
  default     = "cron(0 5 ? * * *)"
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 120
  
  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Backup retention days must be at least 1."
  }
}

variable "backup_cold_storage_days" {
  description = "Number of days before moving backups to cold storage"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_cold_storage_days >= 0
    error_message = "Backup cold storage days must be a positive number."
  }
}

variable "backup_kms_key_arn" {
  description = "ARN of KMS key for backup encryption (optional)"
  type        = string
  default     = null
}

# ==========================================================================
# CORS CONFIGURATION
# ==========================================================================

variable "cors_max_age_seconds" {
  description = "Maximum age for CORS preflight requests in seconds"
  type        = number
  default     = 3000
  
  validation {
    condition     = var.cors_max_age_seconds >= 0
    error_message = "CORS max age must be a positive number."
  }
}

variable "cors_allowed_methods" {
  description = "List of allowed HTTP methods for CORS"
  type        = list(string)
  default     = ["GET", "PUT", "POST", "DELETE", "HEAD"]
  
  validation {
    condition = alltrue([
      for method in var.cors_allowed_methods : 
      contains(["GET", "PUT", "POST", "DELETE", "HEAD", "OPTIONS"], method)
    ])
    error_message = "CORS allowed methods must be valid HTTP methods."
  }
}

# ==========================================================================
# NETWORK CONFIGURATION
# ==========================================================================

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the web app (optional - leave empty for no restrictions)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges : 
      can(cidrhost(cidr, 0))
    ])
    error_message = "All IP ranges must be valid CIDR blocks."
  }
}

# ==========================================================================
# ADVANCED CONFIGURATION
# ==========================================================================

variable "enable_cloudtrail_integration" {
  description = "Enable AWS CloudTrail integration for enhanced audit logging"
  type        = bool
  default     = false
}

variable "enable_config_integration" {
  description = "Enable AWS Config integration for compliance monitoring"
  type        = bool
  default     = false
}

variable "enable_guardduty_integration" {
  description = "Enable Amazon GuardDuty integration for threat detection"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name for the web app (optional)"
  type        = string
  default     = null
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for custom domain (required if custom_domain_name is provided)"
  type        = string
  default     = null
}

# ==========================================================================
# TAGGING CONFIGURATION
# ==========================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key in keys(var.additional_tags) : 
      can(regex("^[a-zA-Z0-9._:/=+@-]*$", key))
    ])
    error_message = "Tag keys must contain only alphanumeric characters and the following special characters: . _ : / = + @ -"
  }
}