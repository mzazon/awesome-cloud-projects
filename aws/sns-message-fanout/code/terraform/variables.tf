# Variables for the message fan-out SNS and SQS infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "message-fanout"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "message_retention_period" {
  description = "Message retention period in seconds (14 days default)"
  type        = number
  default     = 1209600
  
  validation {
    condition     = var.message_retention_period >= 60 && var.message_retention_period <= 1209600
    error_message = "Message retention period must be between 60 seconds and 14 days."
  }
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for SQS messages in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds."
  }
}

variable "dlq_max_receive_count" {
  description = "Maximum number of receives before message goes to DLQ"
  type        = number
  default     = 3
  
  validation {
    condition     = var.dlq_max_receive_count >= 1 && var.dlq_max_receive_count <= 1000
    error_message = "Max receive count must be between 1 and 1000."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2
}

variable "queue_depth_alarm_threshold" {
  description = "Threshold for queue depth alarms"
  type        = map(number)
  default = {
    inventory = 100
    payment   = 50
    shipping  = 75
    analytics = 200
  }
}

variable "sns_delivery_retry_policy" {
  description = "SNS delivery retry policy configuration"
  type = object({
    num_retries          = number
    num_no_delay_retries = number
    min_delay_target     = number
    max_delay_target     = number
    backoff_function     = string
  })
  default = {
    num_retries          = 3
    num_no_delay_retries = 0
    min_delay_target     = 20
    max_delay_target     = 20
    backoff_function     = "linear"
  }
}

variable "message_filter_policies" {
  description = "Message filter policies for each queue subscription"
  type = map(object({
    event_types = list(string)
    priorities  = list(string)
  }))
  default = {
    inventory = {
      event_types = ["inventory_update", "stock_check"]
      priorities  = ["high", "medium"]
    }
    payment = {
      event_types = ["payment_request", "payment_confirmation"]
      priorities  = ["high"]
    }
    shipping = {
      event_types = ["shipping_notification", "delivery_update"]
      priorities  = ["high", "medium", "low"]
    }
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}