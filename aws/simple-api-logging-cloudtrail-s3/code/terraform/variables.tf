# Input Variables for CloudTrail API Logging Infrastructure
# These variables allow customization of the CloudTrail logging solution
# while maintaining security best practices and compliance requirements

variable "trail_name" {
  description = "Name of the CloudTrail trail for API logging"
  type        = string
  default     = "api-logging-trail"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+$", var.trail_name))
    error_message = "Trail name must contain only alphanumeric characters, periods, hyphens, and underscores."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "enable_log_file_validation" {
  description = "Enable CloudTrail log file integrity validation to detect tampering"
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = "Enable multi-region trail to capture API calls from all AWS regions"
  type        = bool
  default     = true
}

variable "include_global_service_events" {
  description = "Include global service events like IAM, CloudFront, and Route53 in the trail"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653)"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period value."
  }
}

variable "s3_bucket_force_destroy" {
  description = "Allow Terraform to destroy the S3 bucket even if it contains objects (useful for testing)"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for security monitoring (e.g., root account usage)"
  type        = bool
  default     = true
}

variable "alarm_notification_email" {
  description = "Email address for receiving CloudWatch alarm notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""

  validation {
    condition = var.alarm_notification_email == "" || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.alarm_notification_email))
    error_message = "If provided, alarm_notification_email must be a valid email address."
  }
}

variable "s3_key_prefix" {
  description = "S3 key prefix for organizing CloudTrail log files"
  type        = string
  default     = "cloudtrail-logs"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._/-]*$", var.s3_key_prefix))
    error_message = "S3 key prefix must contain only alphanumeric characters, periods, hyphens, underscores, and forward slashes."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning for audit trail protection"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable server-side encryption for the S3 bucket"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting CloudTrail logs (leave empty to use default S3 encryption)"
  type        = string
  default     = ""
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9._:/-]+$", k))])
    error_message = "Tag keys must contain only alphanumeric characters, periods, colons, hyphens, underscores, and forward slashes."
  }
}