# Core project configuration
variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "email-automation"

  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 50
    error_message = "Project name must be between 1 and 50 characters."
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

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Email configuration
variable "sender_email" {
  description = "Verified sender email address for SES"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sender_email))
    error_message = "Sender email must be a valid email address."
  }
}

variable "recipient_email" {
  description = "Default recipient email address for testing"
  type        = string
  default     = ""

  validation {
    condition = var.recipient_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.recipient_email))
    error_message = "Recipient email must be a valid email address or empty."
  }
}

variable "verify_email_addresses" {
  description = "Whether to automatically verify email addresses in SES (only for sandbox mode)"
  type        = bool
  default     = true
}

# Lambda configuration
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.11"

  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# EventBridge configuration
variable "enable_eventbridge_custom_bus" {
  description = "Whether to create a custom EventBridge bus"
  type        = bool
  default     = true
}

variable "eventbridge_bus_name" {
  description = "Name for the custom EventBridge bus"
  type        = string
  default     = ""
}

# Monitoring configuration
variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "lambda_error_threshold" {
  description = "Threshold for Lambda error alarm"
  type        = number
  default     = 1
}

variable "ses_bounce_threshold" {
  description = "Threshold for SES bounce alarm"
  type        = number
  default     = 5
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 1

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 100
    error_message = "Alarm evaluation periods must be between 1 and 100."
  }
}

# Email template configuration
variable "email_template_name" {
  description = "Name for the SES email template"
  type        = string
  default     = "NotificationTemplate"
}

variable "email_template_subject" {
  description = "Subject template for emails"
  type        = string
  default     = "{{subject}}"
}

variable "email_template_html" {
  description = "HTML template for emails"
  type        = string
  default     = "<html><body><h2>{{title}}</h2><p>{{message}}</p><p>Timestamp: {{timestamp}}</p><p>Event Source: {{source}}</p></body></html>"
}

variable "email_template_text" {
  description = "Text template for emails"
  type        = string
  default     = "{{title}}\n\n{{message}}\n\nTimestamp: {{timestamp}}\nEvent Source: {{source}}"
}

# Scheduled email configuration
variable "enable_scheduled_emails" {
  description = "Whether to enable scheduled daily email reports"
  type        = bool
  default     = true
}

variable "scheduled_email_cron" {
  description = "Cron expression for scheduled emails (default: 9 AM daily)"
  type        = string
  default     = "cron(0 9 * * ? *)"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}