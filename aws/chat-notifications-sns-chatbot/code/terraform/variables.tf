# Variables for Chat Notifications with SNS and Chatbot Infrastructure
# This file defines all configurable parameters for the infrastructure deployment
# Variables include validation rules to ensure proper values are provided

# ============================================================================
# BASIC CONFIGURATION VARIABLES
# ============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format like 'us-east-1' or 'eu-west-1'."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
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
  default     = "chat-notifications"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 32
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens, and be 32 characters or less."
  }
}

# ============================================================================
# SNS TOPIC CONFIGURATION VARIABLES
# ============================================================================

variable "sns_topic_display_name" {
  description = "Display name for the SNS topic"
  type        = string
  default     = "Team Notifications Topic"

  validation {
    condition     = length(var.sns_topic_display_name) <= 100
    error_message = "SNS topic display name must be 100 characters or less."
  }
}

variable "enable_sns_encryption" {
  description = "Enable server-side encryption for SNS topic using AWS managed KMS key"
  type        = bool
  default     = true
}

variable "sns_delivery_policy" {
  description = "SNS delivery policy JSON to configure retry behavior (optional)"
  type        = string
  default     = null

  validation {
    condition = var.sns_delivery_policy == null || can(jsondecode(var.sns_delivery_policy))
    error_message = "SNS delivery policy must be valid JSON when provided."
  }
}

variable "additional_sns_subscriptions" {
  description = "Additional email addresses or endpoints to subscribe to SNS notifications"
  type = map(object({
    protocol = string
    endpoint = string
    filter_policy = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.additional_sns_subscriptions : 
      contains(["email", "sms", "http", "https", "lambda", "sqs"], v.protocol)
    ])
    error_message = "SNS subscription protocol must be one of: email, sms, http, https, lambda, sqs."
  }
}

# ============================================================================
# CLOUDWATCH ALARM CONFIGURATION VARIABLES
# ============================================================================

variable "cloudwatch_alarm_enabled" {
  description = "Whether to create demo CloudWatch alarms for testing notifications"
  type        = bool
  default     = true
}

variable "cloudwatch_alarm_threshold" {
  description = "CPU utilization threshold for the demo alarm (percentage)"
  type        = number
  default     = 1.0

  validation {
    condition     = var.cloudwatch_alarm_threshold >= 0 && var.cloudwatch_alarm_threshold <= 100
    error_message = "CloudWatch alarm threshold must be between 0 and 100."
  }
}

variable "cloudwatch_alarm_period" {
  description = "Period in seconds for CloudWatch alarm evaluation"
  type        = number
  default     = 300

  validation {
    condition     = var.cloudwatch_alarm_period >= 60 && var.cloudwatch_alarm_period % 60 == 0
    error_message = "CloudWatch alarm period must be at least 60 seconds and a multiple of 60."
  }
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "Number of periods over which data is compared to the specified threshold"
  type        = number
  default     = 1

  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1 && var.cloudwatch_alarm_evaluation_periods <= 10
    error_message = "CloudWatch alarm evaluation periods must be between 1 and 10."
  }
}

variable "cloudwatch_alarm_datapoints_to_alarm" {
  description = "Number of datapoints that must be breaching to trigger the alarm"
  type        = number
  default     = null

  validation {
    condition = var.cloudwatch_alarm_datapoints_to_alarm == null || (
      var.cloudwatch_alarm_datapoints_to_alarm >= 1 && 
      var.cloudwatch_alarm_datapoints_to_alarm <= var.cloudwatch_alarm_evaluation_periods
    )
    error_message = "Datapoints to alarm must be between 1 and the evaluation periods value."
  }
}

# ============================================================================
# AWS CHATBOT SLACK CONFIGURATION VARIABLES
# ============================================================================

variable "slack_channel_id" {
  description = "Slack channel ID where notifications will be sent (e.g., C07EZ1ABC23)"
  type        = string
  default     = ""

  validation {
    condition     = var.slack_channel_id == "" || can(regex("^C[A-Z0-9]{8,}$", var.slack_channel_id))
    error_message = "Slack channel ID must start with 'C' followed by alphanumeric characters, or be empty."
  }
}

variable "slack_team_id" {
  description = "Slack team (workspace) ID (e.g., T07EA123LEP)"
  type        = string
  default     = ""

  validation {
    condition     = var.slack_team_id == "" || can(regex("^T[A-Z0-9]{8,}$", var.slack_team_id))
    error_message = "Slack team ID must start with 'T' followed by alphanumeric characters, or be empty."
  }
}

variable "chatbot_logging_level" {
  description = "Logging level for AWS Chatbot (ERROR, INFO, or NONE)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["ERROR", "INFO", "NONE"], var.chatbot_logging_level)
    error_message = "Chatbot logging level must be one of: ERROR, INFO, NONE."
  }
}

variable "chatbot_user_authorization_required" {
  description = "Whether user authorization is required for AWS Chatbot commands"
  type        = bool
  default     = true
}

variable "chatbot_custom_guardrail_policies" {
  description = "Additional IAM policy ARNs to apply as guardrails for AWS Chatbot"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for policy in var.chatbot_custom_guardrail_policies :
      can(regex("^arn:aws:iam::[0-9]{12}:policy/.*|^arn:aws:iam::aws:policy/.*$", policy))
    ])
    error_message = "All guardrail policies must be valid IAM policy ARNs."
  }
}

# ============================================================================
# AWS CHATBOT TEAMS CONFIGURATION VARIABLES
# ============================================================================

variable "teams_channel_id" {
  description = "Microsoft Teams channel ID where notifications will be sent (optional)"
  type        = string
  default     = ""
}

variable "teams_tenant_id" {
  description = "Microsoft Teams tenant ID (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.teams_tenant_id == "" || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.teams_tenant_id))
    error_message = "Teams tenant ID must be a valid UUID format or empty."
  }
}

variable "teams_team_id" {
  description = "Microsoft Teams team ID (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.teams_team_id == "" || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.teams_team_id))
    error_message = "Teams team ID must be a valid UUID format or empty."
  }
}

# ============================================================================
# TAGGING AND ORGANIZATIONAL VARIABLES
# ============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.tags : can(regex("^[a-zA-Z0-9+\\-=._:/@]+$", k)) && can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]*$", v))
    ])
    error_message = "Tag keys and values must contain only valid characters."
  }
}

# ============================================================================
# OPTIONAL ADVANCED CONFIGURATION VARIABLES
# ============================================================================

variable "enable_cross_region_replication" {
  description = "Enable cross-region SNS topic replication for disaster recovery"
  type        = bool
  default     = false
}

variable "backup_regions" {
  description = "List of backup AWS regions for cross-region replication"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for region in var.backup_regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", region))
    ])
    error_message = "All backup regions must be valid AWS region formats."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for all resources"
  type        = bool
  default     = false
}

variable "notification_retry_attempts" {
  description = "Number of retry attempts for failed SNS notifications"
  type        = number
  default     = 3

  validation {
    condition     = var.notification_retry_attempts >= 1 && var.notification_retry_attempts <= 10
    error_message = "Retry attempts must be between 1 and 10."
  }
}