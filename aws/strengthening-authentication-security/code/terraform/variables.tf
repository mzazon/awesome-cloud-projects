# AWS Configuration Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

# IAM User Configuration
variable "test_user_name" {
  description = "Name for the test IAM user (will have random suffix appended)"
  type        = string
  default     = "test-user"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.test_user_name))
    error_message = "User name must be valid IAM user name characters."
  }
}

variable "force_password_reset" {
  description = "Whether to force password reset on first login"
  type        = bool
  default     = true
}

variable "temporary_password" {
  description = "Temporary password for test user (use secure value in production)"
  type        = string
  default     = "TempPassword123!"
  sensitive   = true
  
  validation {
    condition     = length(var.temporary_password) >= 8
    error_message = "Password must be at least 8 characters long."
  }
}

# MFA Policy Configuration
variable "mfa_policy_name" {
  description = "Name for the MFA enforcement policy (will have random suffix appended)"
  type        = string
  default     = "EnforceMFA"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.mfa_policy_name))
    error_message = "Policy name must be valid IAM policy name characters."
  }
}

variable "admin_group_name" {
  description = "Name for the MFA administrators group (will have random suffix appended)"
  type        = string
  default     = "MFAAdmins"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]+$", var.admin_group_name))
    error_message = "Group name must be valid IAM group name characters."
  }
}

# CloudTrail Configuration
variable "enable_cloudtrail" {
  description = "Whether to enable CloudTrail for MFA monitoring"
  type        = bool
  default     = true
}

variable "cloudtrail_name" {
  description = "Name for the CloudTrail trail"
  type        = string
  default     = "mfa-audit-trail"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.cloudtrail_name))
    error_message = "CloudTrail name must contain only alphanumeric characters, periods, underscores, and hyphens."
  }
}

variable "s3_bucket_name" {
  description = "Name for S3 bucket to store CloudTrail logs (will have random suffix appended)"
  type        = string
  default     = "mfa-cloudtrail-logs"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.s3_bucket_name))
    error_message = "S3 bucket name must be lowercase and contain only alphanumeric characters, periods, and hyphens."
  }
}

# CloudWatch Configuration
variable "enable_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard for MFA monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name for the CloudWatch dashboard"
  type        = string
  default     = "MFA-Security-Dashboard"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.dashboard_name))
    error_message = "Dashboard name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "enable_mfa_alarms" {
  description = "Whether to create CloudWatch alarms for MFA events"
  type        = bool
  default     = true
}

# SNS Configuration for Alerts
variable "enable_sns_notifications" {
  description = "Whether to enable SNS notifications for MFA alerts"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for MFA security notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address or empty string."
  }
}

# Additional Security Configuration
variable "enable_config_rules" {
  description = "Whether to enable AWS Config rules for MFA compliance"
  type        = bool
  default     = false
}

variable "enable_security_hub" {
  description = "Whether to enable Security Hub findings for MFA compliance"
  type        = bool
  default     = false
}

# Resource Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}