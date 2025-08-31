# Variables for Community Knowledge Base with re:Post Private and SNS infrastructure
# This configuration defines all customizable parameters for the knowledge base notification system

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "community-knowledge-base"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "notification_email_addresses" {
  description = "List of email addresses to receive knowledge base notifications"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.notification_email_addresses : can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid email formats."
  }
}

variable "sns_topic_name" {
  description = "Name for the SNS topic (will be prefixed with project name and suffixed with random string)"
  type        = string
  default     = "knowledge-notifications"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.sns_topic_name))
    error_message = "SNS topic name must contain only alphanumeric characters, underscores, and hyphens."
  }
}

variable "sns_display_name" {
  description = "Human-readable display name for the SNS topic"
  type        = string
  default     = "Knowledge Base Notifications"

  validation {
    condition     = length(var.sns_display_name) <= 100
    error_message = "SNS display name must be 100 characters or less."
  }
}

variable "enable_sns_encryption" {
  description = "Enable server-side encryption for SNS topic using AWS managed KMS key"
  type        = bool
  default     = true
}

variable "sns_message_retention_seconds" {
  description = "Number of seconds SNS will retain messages for delivery retry"
  type        = number
  default     = 1209600 # 14 days

  validation {
    condition     = var.sns_message_retention_seconds >= 60 && var.sns_message_retention_seconds <= 1209600
    error_message = "Message retention must be between 60 seconds (1 minute) and 1209600 seconds (14 days)."
  }
}

variable "email_delivery_retry_policy" {
  description = "Delivery retry policy configuration for email subscriptions"
  type = object({
    num_retries         = number
    min_delay_target    = number
    max_delay_target    = number
    backoff_function    = string
  })
  default = {
    num_retries         = 3
    min_delay_target    = 20
    max_delay_target    = 20
    backoff_function    = "linear"
  }

  validation {
    condition     = contains(["linear", "arithmetic", "geometric", "exponential"], var.email_delivery_retry_policy.backoff_function)
    error_message = "Backoff function must be one of: linear, arithmetic, geometric, exponential."
  }

  validation {
    condition     = var.email_delivery_retry_policy.num_retries >= 0 && var.email_delivery_retry_policy.num_retries <= 100
    error_message = "Number of retries must be between 0 and 100."
  }
}

variable "notification_filter_policy" {
  description = "JSON filter policy to control which messages are delivered to subscribers"
  type        = string
  default     = null

  validation {
    condition = var.notification_filter_policy == null || can(jsondecode(var.notification_filter_policy))
    error_message = "Filter policy must be valid JSON or null."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for SNS topic monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_alarm_email" {
  description = "Email address for CloudWatch alarm notifications (separate from knowledge base notifications)"
  type        = string
  default     = null

  validation {
    condition = var.cloudwatch_alarm_email == null || can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.cloudwatch_alarm_email))
    error_message = "CloudWatch alarm email must be a valid email address or null."
  }
}

variable "failed_message_alarm_threshold" {
  description = "Number of failed message deliveries that triggers an alarm"
  type        = number
  default     = 1

  validation {
    condition     = var.failed_message_alarm_threshold >= 1
    error_message = "Failed message alarm threshold must be at least 1."
  }
}

variable "enable_dead_letter_queue" {
  description = "Enable SQS dead letter queue for failed message deliveries"
  type        = bool
  default     = false
}

variable "dlq_max_receive_count" {
  description = "Maximum number of times a message can be received before being sent to the dead letter queue"
  type        = number
  default     = 3

  validation {
    condition     = var.dlq_max_receive_count >= 1 && var.dlq_max_receive_count <= 1000
    error_message = "DLQ max receive count must be between 1 and 1000."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.additional_tags : can(regex("^[\\w\\s+=.:/\\-@]*$", key)) && can(regex("^[\\w\\s+=.:/\\-@]*$", value))
    ])
    error_message = "Tag keys and values must contain only alphanumeric characters, spaces, and the characters: + = . : / - @"
  }
}

variable "organization_name" {
  description = "Organization name for documentation and resource naming context"
  type        = string
  default     = "Enterprise"

  validation {
    condition     = length(var.organization_name) > 0 && length(var.organization_name) <= 64
    error_message = "Organization name must be between 1 and 64 characters."
  }
}