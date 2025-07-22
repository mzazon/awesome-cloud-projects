# AWS Region
variable "aws_region" {
  description = "AWS region for IoT Device Defender resources"
  type        = string
  default     = "us-east-1"
}

# Environment identifier
variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# Email address for security alerts
variable "notification_email" {
  description = "Email address to receive security alert notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

# Random suffix for unique resource naming
variable "random_suffix" {
  description = "Random suffix for unique resource naming (will be generated if not provided)"
  type        = string
  default     = ""
}

# Security profile behavioral thresholds
variable "security_thresholds" {
  description = "Threshold values for IoT security behavioral monitoring"
  type = object({
    max_messages_per_5min          = number
    max_authorization_failures     = number
    max_message_size_bytes        = number
    max_connection_attempts_per_5min = number
  })
  default = {
    max_messages_per_5min          = 100
    max_authorization_failures     = 5
    max_message_size_bytes        = 1024
    max_connection_attempts_per_5min = 20
  }
}

# Enable ML-based threat detection
variable "enable_ml_detection" {
  description = "Enable machine learning based threat detection"
  type        = bool
  default     = true
}

# Audit frequency configuration
variable "audit_schedule" {
  description = "Schedule configuration for automated security audits"
  type = object({
    frequency   = string
    day_of_week = string
  })
  default = {
    frequency   = "WEEKLY"
    day_of_week = "MON"
  }
  
  validation {
    condition     = contains(["DAILY", "WEEKLY", "BIWEEKLY", "MONTHLY"], var.audit_schedule.frequency)
    error_message = "Audit frequency must be DAILY, WEEKLY, BIWEEKLY, or MONTHLY."
  }
  
  validation {
    condition = contains(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], var.audit_schedule.day_of_week)
    error_message = "Day of week must be SUN, MON, TUE, WED, THU, FRI, or SAT."
  }
}

# Security profile target scope
variable "security_profile_target" {
  description = "Target scope for security profile application"
  type        = string
  default     = "all-registered-things"
  
  validation {
    condition     = contains(["all-registered-things", "thing-group"], var.security_profile_target)
    error_message = "Security profile target must be 'all-registered-things' or 'thing-group'."
  }
}

# Thing group name (only used if security_profile_target is "thing-group")
variable "thing_group_name" {
  description = "Name of the thing group to apply security profile to (only used if security_profile_target is 'thing-group')"
  type        = string
  default     = ""
}

# CloudWatch alarm configuration
variable "cloudwatch_alarm_config" {
  description = "Configuration for CloudWatch alarms"
  type = object({
    evaluation_periods = number
    period_seconds    = number
    threshold         = number
  })
  default = {
    evaluation_periods = 1
    period_seconds    = 300
    threshold         = 1
  }
}

# Enable comprehensive audit checks
variable "audit_checks" {
  description = "Configuration for IoT Device Defender audit checks"
  type = object({
    authenticated_cognito_role_overly_permissive = bool
    ca_certificate_expiring                     = bool
    conflicting_client_ids                      = bool
    device_certificate_expiring                 = bool
    device_certificate_shared                   = bool
    iot_policy_overly_permissive               = bool
    logging_disabled                           = bool
    revoked_ca_certificate_still_active       = bool
    revoked_device_certificate_still_active   = bool
    unauthenticated_cognito_role_overly_permissive = bool
  })
  default = {
    authenticated_cognito_role_overly_permissive = true
    ca_certificate_expiring                     = true
    conflicting_client_ids                      = true
    device_certificate_expiring                 = true
    device_certificate_shared                   = true
    iot_policy_overly_permissive               = true
    logging_disabled                           = true
    revoked_ca_certificate_still_active       = true
    revoked_device_certificate_still_active   = true
    unauthenticated_cognito_role_overly_permissive = true
  }
}