# Variables for mobile push notifications with Pinpoint infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region name."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming and tagging)"
  type        = string
  default     = "ecommerce-mobile-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "application_name" {
  description = "Name of the Pinpoint application"
  type        = string
  default     = "ecommerce-mobile-push"
  
  validation {
    condition     = length(var.application_name) > 0 && length(var.application_name) <= 64
    error_message = "Application name must be between 1 and 64 characters."
  }
}

# Push Notification Configuration
variable "apns_certificate_file" {
  description = "Path to APNs certificate file (optional - set if enabling APNs)"
  type        = string
  default     = ""
}

variable "apns_private_key_file" {
  description = "Path to APNs private key file (optional - set if enabling APNs)"
  type        = string
  default     = ""
}

variable "apns_bundle_id" {
  description = "iOS application bundle ID for APNs"
  type        = string
  default     = "com.example.ecommerce"
}

variable "fcm_server_key" {
  description = "Firebase Cloud Messaging server key for Android notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_apns" {
  description = "Enable Apple Push Notification Service (APNs) channel"
  type        = bool
  default     = false
}

variable "enable_fcm" {
  description = "Enable Firebase Cloud Messaging (FCM) channel"
  type        = bool
  default     = false
}

# Segment Configuration
variable "segment_name" {
  description = "Name of the user segment for targeting"
  type        = string
  default     = "high-value-customers"
}

variable "segment_criteria_attribute" {
  description = "User attribute for segment criteria"
  type        = string
  default     = "PurchaseHistory"
}

variable "segment_criteria_values" {
  description = "Values for segment criteria filtering"
  type        = list(string)
  default     = ["high-value"]
}

# Campaign Configuration
variable "campaign_name" {
  description = "Name of the push notification campaign"
  type        = string
  default     = "flash-sale-notification"
}

variable "campaign_description" {
  description = "Description of the push notification campaign"
  type        = string
  default     = "Flash sale notification for high-value customers"
}

variable "notification_title" {
  description = "Title for push notifications"
  type        = string
  default     = "🔥 Flash Sale Alert"
}

variable "notification_body" {
  description = "Body text for push notifications"
  type        = string
  default     = "Don't miss out! Flash sale ends in 2 hours - Up to 50% off!"
}

variable "quiet_time_start" {
  description = "Start time for quiet hours (24-hour format, e.g., '22:00')"
  type        = string
  default     = "22:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.quiet_time_start))
    error_message = "Quiet time start must be in HH:MM format (24-hour)."
  }
}

variable "quiet_time_end" {
  description = "End time for quiet hours (24-hour format, e.g., '08:00')"
  type        = string
  default     = "08:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.quiet_time_end))
    error_message = "Quiet time end must be in HH:MM format (24-hour)."
  }
}

variable "campaign_timezone" {
  description = "Timezone for campaign scheduling"
  type        = string
  default     = "America/New_York"
}

# Analytics Configuration
variable "enable_event_streaming" {
  description = "Enable event streaming to Kinesis for advanced analytics"
  type        = bool
  default     = true
}

variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis stream"
  type        = number
  default     = 1
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 100
    error_message = "Kinesis shard count must be between 1 and 100."
  }
}

# Monitoring Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "failure_threshold" {
  description = "Threshold for push notification failures alarm"
  type        = number
  default     = 5
  
  validation {
    condition     = var.failure_threshold > 0
    error_message = "Failure threshold must be greater than 0."
  }
}

variable "delivery_rate_threshold" {
  description = "Minimum delivery rate threshold (as decimal, e.g., 0.9 for 90%)"
  type        = number
  default     = 0.9
  
  validation {
    condition     = var.delivery_rate_threshold >= 0.0 && var.delivery_rate_threshold <= 1.0
    error_message = "Delivery rate threshold must be between 0.0 and 1.0."
  }
}

variable "alarm_notification_email" {
  description = "Email address for CloudWatch alarm notifications (optional)"
  type        = string
  default     = ""
}

# Test Endpoints Configuration
variable "create_test_endpoints" {
  description = "Create test endpoints for validation"
  type        = bool
  default     = true
}

variable "test_ios_device_token" {
  description = "Test iOS device token for validation"
  type        = string
  default     = "test-ios-device-token-001"
}

variable "test_android_device_token" {
  description = "Test Android device token for validation"
  type        = string
  default     = "test-android-device-token-001"
}

# Template Configuration
variable "create_push_template" {
  description = "Create reusable push notification template"
  type        = bool
  default     = true
}

variable "template_name" {
  description = "Name of the push notification template"
  type        = string
  default     = "flash-sale-template"
}