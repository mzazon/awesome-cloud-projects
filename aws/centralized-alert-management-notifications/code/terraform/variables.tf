# =============================================================================
# VARIABLES - Centralized Alert Management with User Notifications
# =============================================================================
# This file defines all configurable parameters for the centralized alert
# management infrastructure. Customize these values to match your environment
# requirements and monitoring thresholds.
# =============================================================================

# =============================================================================
# GENERAL CONFIGURATION
# =============================================================================

variable "name_prefix" {
  description = "Prefix for all resource names to ensure uniqueness and organization"
  type        = string
  default     = "alert-mgmt"
  
  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.name_prefix))
    error_message = "Name prefix must be 1-20 characters long and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and identification"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources for consistent resource management"
  type        = map(string)
  default = {
    Owner       = "DevOps Team"
    Project     = "Centralized Alert Management"
    Terraform   = "true"
    CostCenter  = "Engineering"
  }
}

# =============================================================================
# NOTIFICATION CONFIGURATION
# =============================================================================

variable "notification_email" {
  description = "Email address to receive notifications from the alert management system"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "contact_team" {
  description = "Team name associated with the notification contact for organizational purposes"
  type        = string
  default     = "Operations"
}

variable "notification_aggregation_duration" {
  description = "Time window for aggregating notifications to prevent alert flooding"
  type        = string
  default     = "SHORT"
  
  validation {
    condition     = contains(["SHORT", "LONG", "NONE"], var.notification_aggregation_duration)
    error_message = "Aggregation duration must be SHORT (5 minutes), LONG (12 hours), or NONE."
  }
}

# =============================================================================
# S3 MONITORING THRESHOLDS
# =============================================================================

variable "bucket_size_threshold_bytes" {
  description = "S3 bucket size threshold in bytes that triggers the size alarm"
  type        = number
  default     = 5000000  # 5 MB - suitable for demo purposes
  
  validation {
    condition     = var.bucket_size_threshold_bytes > 0
    error_message = "Bucket size threshold must be greater than 0 bytes."
  }
}

variable "object_count_threshold" {
  description = "Number of objects threshold that triggers the object count alarm"
  type        = number
  default     = 10
  
  validation {
    condition     = var.object_count_threshold > 0
    error_message = "Object count threshold must be greater than 0."
  }
}

variable "bucket_size_alarm_evaluation_periods" {
  description = "Number of evaluation periods for bucket size alarm before triggering"
  type        = number
  default     = 1
  
  validation {
    condition     = var.bucket_size_alarm_evaluation_periods >= 1 && var.bucket_size_alarm_evaluation_periods <= 5
    error_message = "Evaluation periods must be between 1 and 5."
  }
}

variable "object_count_alarm_evaluation_periods" {
  description = "Number of evaluation periods for object count alarm before triggering"
  type        = number
  default     = 1
  
  validation {
    condition     = var.object_count_alarm_evaluation_periods >= 1 && var.object_count_alarm_evaluation_periods <= 5
    error_message = "Evaluation periods must be between 1 and 5."
  }
}

# =============================================================================
# S3 METRICS CONFIGURATION
# =============================================================================

variable "enable_request_metrics" {
  description = "Enable S3 request metrics for detailed access pattern monitoring (incurs additional charges)"
  type        = bool
  default     = false
}

variable "request_metrics_prefix" {
  description = "S3 object prefix to filter request metrics monitoring (empty string monitors all objects)"
  type        = string
  default     = ""
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9!_.*'()-/]*$", var.request_metrics_prefix))
    error_message = "Request metrics prefix contains invalid characters. Use only alphanumeric characters and these symbols: !_.*'()-/"
  }
}

# =============================================================================
# TESTING AND DEMO CONFIGURATION
# =============================================================================

variable "create_sample_data" {
  description = "Create sample data objects in S3 bucket for testing metrics and alarms"
  type        = bool
  default     = true
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "enable_s3_event_notifications" {
  description = "Enable S3 event notifications to EventBridge for additional monitoring capabilities"
  type        = bool
  default     = false
}

variable "alarm_actions_enabled" {
  description = "Enable or disable alarm actions (useful for testing without triggering notifications)"
  type        = bool
  default     = true
}

variable "custom_alarm_actions" {
  description = "Additional SNS topic ARNs to notify when alarms trigger (optional)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for arn in var.custom_alarm_actions : can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_-]+$", arn))
    ])
    error_message = "All custom alarm actions must be valid SNS topic ARNs."
  }
}

# =============================================================================
# REGIONAL AND MULTI-REGION CONFIGURATION
# =============================================================================

variable "additional_notification_regions" {
  description = "Additional AWS regions for notification processing (for multi-region setups)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for region in var.additional_notification_regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", region))
    ])
    error_message = "All additional regions must be valid AWS region identifiers (e.g., us-west-2, eu-central-1)."
  }
}

# =============================================================================
# COST OPTIMIZATION SETTINGS
# =============================================================================

variable "enable_lifecycle_configuration" {
  description = "Enable S3 lifecycle configuration to automatically transition objects to cheaper storage classes"
  type        = bool
  default     = false
}

variable "lifecycle_transition_days" {
  description = "Number of days after which objects transition to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lifecycle_transition_days >= 1
    error_message = "Lifecycle transition days must be at least 1."
  }
}

variable "lifecycle_expiration_days" {
  description = "Number of days after which objects are automatically deleted (0 = no expiration)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.lifecycle_expiration_days >= 0
    error_message = "Lifecycle expiration days must be 0 or greater."
  }
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "enable_bucket_logging" {
  description = "Enable S3 server access logging for audit and security monitoring"
  type        = bool
  default     = false
}

variable "logging_bucket_name" {
  description = "Name of existing S3 bucket for storing access logs (required if bucket logging is enabled)"
  type        = string
  default     = ""
}

variable "enable_bucket_notification_encryption" {
  description = "Enable encryption for S3 event notifications (recommended for production)"
  type        = bool
  default     = true
}

# =============================================================================
# MONITORING AND OBSERVABILITY
# =============================================================================

variable "enable_cloudwatch_insights" {
  description = "Enable additional CloudWatch Insights queries for advanced log analysis"
  type        = bool
  default     = false
}

variable "alarm_comparison_operators" {
  description = "Map of alarm names to comparison operators for custom threshold behavior"
  type        = map(string)
  default = {
    bucket_size    = "GreaterThanThreshold"
    object_count   = "GreaterThanThreshold"
  }
  
  validation {
    condition = alltrue([
      for operator in values(var.alarm_comparison_operators) : 
      contains([
        "GreaterThanOrEqualToThreshold",
        "GreaterThanThreshold", 
        "LessThanThreshold",
        "LessThanOrEqualToThreshold"
      ], operator)
    ])
    error_message = "Comparison operators must be valid CloudWatch alarm operators."
  }
}

variable "enable_dashboard" {
  description = "Create CloudWatch dashboard for visualization of S3 metrics and alarm states"
  type        = bool
  default     = false
}

# =============================================================================
# COMPLIANCE AND GOVERNANCE
# =============================================================================

variable "require_mfa_delete" {
  description = "Require MFA for S3 object deletion (can only be enabled by root user via CLI)"
  type        = bool
  default     = false
}

variable "compliance_tags" {
  description = "Additional compliance-related tags for governance and audit purposes"
  type        = map(string)
  default = {
    DataClassification = "Internal"
    ComplianceScope    = "Monitoring"
    RetentionPeriod    = "1-Year"
  }
}