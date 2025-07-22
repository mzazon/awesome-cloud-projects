# Input variables for AWS serverless email processing system

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "domain_name" {
  description = "Verified domain name for SES email receiving (must be verified in SES)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain format."
  }
}

variable "email_addresses" {
  description = "List of email addresses that will receive emails (e.g., support@domain.com, invoices@domain.com)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for email in var.email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be in valid email format."
  }
}

variable "notification_email" {
  description = "Email address to receive SNS notifications about email processing"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "s3_bucket_name" {
  description = "Name for S3 bucket to store emails (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "enable_email_encryption" {
  description = "Enable S3 bucket encryption for stored emails"
  type        = bool
  default     = true
}

variable "email_retention_days" {
  description = "Number of days to retain emails in S3 before automatic deletion"
  type        = number
  default     = 30
  
  validation {
    condition     = var.email_retention_days >= 1 && var.email_retention_days <= 3653
    error_message = "Email retention days must be between 1 and 3653 (10 years)."
  }
}

variable "ses_region" {
  description = "AWS region for SES email receiving (must support SES receiving)"
  type        = string
  default     = ""
  
  validation {
    condition = var.ses_region == "" || contains([
      "us-east-1", "us-west-2", "eu-west-1"
    ], var.ses_region)
    error_message = "SES region must be one of: us-east-1, us-west-2, eu-west-1 (or empty for current region)."
  }
}

variable "create_sns_subscription" {
  description = "Automatically create SNS email subscription for notifications"
  type        = bool
  default     = true
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention period for Lambda function logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.lambda_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for Lambda function"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}