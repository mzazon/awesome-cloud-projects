# AWS Configuration
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
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Security Automation Configuration
variable "automation_prefix" {
  description = "Prefix for all security automation resources"
  type        = string
  default     = "security-automation"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
}

# Security Hub Configuration
variable "security_hub_enabled" {
  description = "Whether Security Hub is enabled in the account"
  type        = bool
  default     = true
}

variable "enable_automation_rules" {
  description = "Whether to create Security Hub automation rules"
  type        = bool
  default     = true
}

variable "enable_custom_actions" {
  description = "Whether to create custom Security Hub actions"
  type        = bool
  default     = true
}

# EventBridge Configuration
variable "event_rule_state" {
  description = "State of EventBridge rules (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.event_rule_state)
    error_message = "Event rule state must be either ENABLED or DISABLED."
  }
}

variable "finding_severities" {
  description = "List of finding severities to process"
  type        = list(string)
  default     = ["HIGH", "CRITICAL", "MEDIUM"]
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for security notifications (optional)"
  type        = string
  default     = ""
}

variable "sns_delivery_policy" {
  description = "SNS topic delivery policy configuration"
  type = object({
    min_delay_target = number
    max_delay_target = number
    num_retries      = number
  })
  default = {
    min_delay_target = 5
    max_delay_target = 300
    num_retries      = 10
  }
}

# Dead Letter Queue Configuration
variable "dlq_message_retention_period" {
  description = "Message retention period for DLQ in seconds"
  type        = number
  default     = 1209600 # 14 days
}

variable "dlq_visibility_timeout" {
  description = "Visibility timeout for DLQ in seconds"
  type        = number
  default     = 300
}

# CloudWatch Configuration
variable "enable_cloudwatch_monitoring" {
  description = "Whether to create CloudWatch alarms and dashboard"
  type        = bool
  default     = true
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 1
}

variable "cloudwatch_alarm_threshold" {
  description = "Threshold for CloudWatch alarms"
  type        = number
  default     = 1
}

# Systems Manager Configuration
variable "enable_ssm_automation" {
  description = "Whether to create Systems Manager automation documents"
  type        = bool
  default     = true
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}