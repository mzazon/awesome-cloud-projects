# General Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "mobile-ab-testing"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,50}$", var.project_name))
    error_message = "Project name must be alphanumeric with hyphens, 1-50 characters."
  }
}

# Pinpoint Configuration
variable "pinpoint_application_name" {
  description = "Name of the Pinpoint application"
  type        = string
  default     = "Mobile AB Testing App"
}

variable "enable_analytics_export" {
  description = "Enable analytics export to S3"
  type        = bool
  default     = true
}

variable "enable_event_stream" {
  description = "Enable event streaming to Kinesis"
  type        = bool
  default     = true
}

# Push Notification Configuration
variable "firebase_server_key" {
  description = "Firebase server key for Android push notifications (GCM/FCM)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "apns_certificate" {
  description = "Base64 encoded APNS certificate for iOS push notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "apns_private_key" {
  description = "Base64 encoded APNS private key for iOS push notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "apns_bundle_id" {
  description = "Bundle ID for iOS app (required for APNS)"
  type        = string
  default     = ""
}

variable "apns_team_id" {
  description = "Apple Developer Team ID (required for APNS)"
  type        = string
  default     = ""
}

variable "apns_key_id" {
  description = "APNS key ID (required for token-based APNS)"
  type        = string
  default     = ""
}

variable "enable_apns_sandbox" {
  description = "Enable APNS sandbox mode for development"
  type        = bool
  default     = true
}

# Campaign Configuration
variable "campaign_name" {
  description = "Name of the A/B test campaign"
  type        = string
  default     = "Push Notification A/B Test"
}

variable "campaign_description" {
  description = "Description of the A/B test campaign"
  type        = string
  default     = "Testing different push notification messages for user engagement"
}

variable "holdout_percentage" {
  description = "Percentage of users to hold out from the campaign (0-50)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.holdout_percentage >= 0 && var.holdout_percentage <= 50
    error_message = "Holdout percentage must be between 0 and 50."
  }
}

variable "treatment_percentage" {
  description = "Percentage of users for each treatment (control + treatments should equal 100 - holdout)"
  type        = number
  default     = 45
  
  validation {
    condition     = var.treatment_percentage >= 10 && var.treatment_percentage <= 90
    error_message = "Treatment percentage must be between 10 and 90."
  }
}

# Kinesis Configuration
variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis stream"
  type        = number
  default     = 1
  
  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 10
    error_message = "Kinesis shard count must be between 1 and 10."
  }
}

variable "kinesis_retention_period" {
  description = "Kinesis stream retention period in hours"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 168
    error_message = "Kinesis retention period must be between 24 and 168 hours."
  }
}

# CloudWatch Configuration
variable "create_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  type        = string
  default     = "Pinpoint-AB-Testing-Dashboard"
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for analytics export (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "s3_force_destroy" {
  description = "Force destroy S3 bucket and all objects on terraform destroy"
  type        = bool
  default     = false
}

# Lambda Configuration
variable "create_winner_selection_lambda" {
  description = "Create Lambda function for automated winner selection"
  type        = bool
  default     = true
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for winner selection"
  type        = string
  default     = "pinpoint-winner-selection"
}

# Segment Configuration
variable "app_versions" {
  description = "List of app versions to include in the active users segment"
  type        = list(string)
  default     = ["1.0.0", "1.1.0", "1.2.0"]
}

variable "high_value_session_threshold" {
  description = "Minimum number of sessions to qualify as high-value user"
  type        = number
  default     = 5
  
  validation {
    condition     = var.high_value_session_threshold >= 1 && var.high_value_session_threshold <= 100
    error_message = "Session threshold must be between 1 and 100."
  }
}

variable "high_value_recency_days" {
  description = "Number of days for high-value user recency (1-30)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.high_value_recency_days >= 1 && var.high_value_recency_days <= 30
    error_message = "Recency days must be between 1 and 30."
  }
}

# Campaign Limits
variable "campaign_daily_limit" {
  description = "Daily message limit for campaigns"
  type        = number
  default     = 1000
}

variable "campaign_total_limit" {
  description = "Total message limit for campaigns"
  type        = number
  default     = 10000
}

variable "campaign_messages_per_second" {
  description = "Messages per second limit for campaigns"
  type        = number
  default     = 100
}

# Message Content
variable "control_message_title" {
  description = "Title for control message"
  type        = string
  default     = "New Updates Available"
}

variable "control_message_body" {
  description = "Body for control message"
  type        = string
  default     = "🎯 Control Message: Check out our new features!"
}

variable "personalized_message_title" {
  description = "Title for personalized message"
  type        = string
  default     = "Personalized Updates"
}

variable "personalized_message_body" {
  description = "Body for personalized message"
  type        = string
  default     = "🚀 Hi {{User.FirstName}}, discover features made just for you!"
}

variable "urgent_message_title" {
  description = "Title for urgent message"
  type        = string
  default     = "Limited Time Offer"
}

variable "urgent_message_body" {
  description = "Body for urgent message"
  type        = string
  default     = "⚡ Don't miss out! Limited time features available now!"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}