# AWS Transfer Family Web Apps - Terraform Variables
# This file defines all configurable parameters for the Simple File Sharing solution

# =============================================================================
# General Configuration Variables
# =============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
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
  default     = "simple-file-sharing"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = null # Will use provider default region
}

# =============================================================================
# S3 Storage Configuration
# =============================================================================

variable "bucket_name_override" {
  description = "Override for S3 bucket name (if not provided, will be auto-generated)"
  type        = string
  default     = null
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket for file history tracking"
  type        = bool
  default     = true
}

variable "s3_storage_class" {
  description = "Default storage class for uploaded files"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD",
      "STANDARD_IA",
      "ONEZONE_IA",
      "REDUCED_REDUNDANCY",
      "GLACIER",
      "DEEP_ARCHIVE",
      "INTELLIGENT_TIERING"
    ], var.s3_storage_class)
    error_message = "Storage class must be a valid S3 storage class."
  }
}

variable "lifecycle_rules_enabled" {
  description = "Enable S3 lifecycle rules for cost optimization"
  type        = bool
  default     = true
}

variable "transition_to_ia_days" {
  description = "Number of days after which objects transition to IA storage class"
  type        = number
  default     = 30
  validation {
    condition     = var.transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "transition_to_glacier_days" {
  description = "Number of days after which objects transition to Glacier"
  type        = number
  default     = 90
  validation {
    condition     = var.transition_to_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

variable "expire_objects_days" {
  description = "Number of days after which objects are automatically deleted (0 = never)"
  type        = number
  default     = 0
  validation {
    condition     = var.expire_objects_days >= 0
    error_message = "Expiration days must be a non-negative number."
  }
}

# =============================================================================
# IAM Identity Center Configuration
# =============================================================================

variable "identity_center_arn_override" {
  description = "Override for IAM Identity Center ARN (if not provided, will be auto-detected)"
  type        = string
  default     = null
  validation {
    condition = var.identity_center_arn_override == null || can(regex("^arn:aws:sso:::instance/ssoins-[a-f0-9]{16}$", var.identity_center_arn_override))
    error_message = "Identity Center ARN must be in the format: arn:aws:sso:::instance/ssoins-xxxxxxxxxxxxxxxx"
  }
}

# =============================================================================
# Demo User Configuration
# =============================================================================

variable "demo_users" {
  description = "Map of demo users to create for testing the file sharing solution"
  type = map(object({
    display_name = string
    given_name   = string
    family_name  = string
    email        = string
  }))
  default = {
    "demo-user" = {
      display_name = "Demo File Sharing User"
      given_name   = "Demo"
      family_name  = "User"
      email        = "demo@example.com"
    }
  }
  validation {
    condition = alltrue([
      for user in var.demo_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", user.email))
    ])
    error_message = "All user emails must be valid email addresses."
  }
}

variable "demo_groups" {
  description = "Map of demo groups to create for organized access management"
  type = map(object({
    description = string
  }))
  default = {
    "file-sharing-users" = {
      description = "Users with access to the file sharing web application"
    }
    "file-sharing-admins" = {
      description = "Administrators with full access to file sharing resources"
    }
  }
}

variable "group_memberships" {
  description = "Map defining which users belong to which groups"
  type = map(object({
    user  = string
    group = string
  }))
  default = {
    "demo-user-membership" = {
      user  = "demo-user"
      group = "file-sharing-users"
    }
  }
}

# =============================================================================
# S3 Access Grants Configuration
# =============================================================================

variable "user_access_grants" {
  description = "Map of access grants for individual users"
  type = map(object({
    permission = string # READ, WRITE, or READWRITE
    prefix     = string # S3 prefix for user access scope
  }))
  default = {
    "demo-user" = {
      permission = "READWRITE"
      prefix     = "users/demo-user/*"
    }
  }
  validation {
    condition = alltrue([
      for grant in var.user_access_grants : contains(["READ", "WRITE", "READWRITE"], grant.permission)
    ])
    error_message = "Access grant permissions must be READ, WRITE, or READWRITE."
  }
}

variable "group_access_grants" {
  description = "Map of access grants for groups"
  type = map(object({
    permission = string # READ, WRITE, or READWRITE
    prefix     = string # S3 prefix for group access scope
  }))
  default = {
    "file-sharing-users" = {
      permission = "READWRITE"
      prefix     = "shared/*"
    }
  }
  validation {
    condition = alltrue([
      for grant in var.group_access_grants : contains(["READ", "WRITE", "READWRITE"], grant.permission)
    ])
    error_message = "Access grant permissions must be READ, WRITE, or READWRITE."
  }
}

# =============================================================================
# Monitoring and Logging Configuration
# =============================================================================

variable "enable_cloudwatch_logging" {
  description = "Enable CloudWatch logging for monitoring file sharing activities"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for auditing S3 and IAM activities"
  type        = bool
  default     = true
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "enable_bucket_encryption" {
  description = "Enable server-side encryption for the S3 bucket"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for S3 bucket encryption (if not provided, uses AWS managed key)"
  type        = string
  default     = null
}

variable "enable_bucket_public_access_block" {
  description = "Enable S3 bucket public access block settings"
  type        = bool
  default     = true
}

variable "enable_bucket_notifications" {
  description = "Enable S3 bucket notifications for file upload/download events"
  type        = bool
  default     = false
}

# =============================================================================
# Cost Optimization Configuration
# =============================================================================

variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering for automatic cost optimization"
  type        = bool
  default     = false
}

variable "enable_request_metrics" {
  description = "Enable S3 request metrics for monitoring access patterns"
  type        = bool
  default     = false
}

# =============================================================================
# Tags Configuration
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cost_center" {
  description = "Cost center tag for billing allocation"
  type        = string
  default     = "shared-services"
}

variable "data_classification" {
  description = "Data classification tag for the file sharing solution"
  type        = string
  default     = "internal"
  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Data classification must be one of: public, internal, confidential, restricted."
  }
}

# =============================================================================
# Transfer Family Configuration (for future use)
# =============================================================================
# Note: These variables are prepared for when Terraform support for 
# Transfer Family Web Apps becomes available

variable "transfer_web_app_name" {
  description = "Name for the Transfer Family Web App (future use)"
  type        = string
  default     = null
}

variable "enable_custom_domain" {
  description = "Enable custom domain for the Transfer Family Web App (future use)"
  type        = bool
  default     = false
}

variable "custom_domain_name" {
  description = "Custom domain name for the Transfer Family Web App (future use)"
  type        = string
  default     = null
  validation {
    condition = var.custom_domain_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$", var.custom_domain_name))
    error_message = "Custom domain name must be a valid DNS name."
  }
}