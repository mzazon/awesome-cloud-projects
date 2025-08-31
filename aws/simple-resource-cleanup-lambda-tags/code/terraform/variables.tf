# Input variables for the resource cleanup automation infrastructure
# These variables allow customization of the deployment while maintaining
# security best practices and operational flexibility

variable "environment" {
  description = "Environment name for resource tagging and naming (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, test, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "resource-cleanup"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cost_center" {
  description = "Cost center identifier for billing and cost allocation"
  type        = string
  default     = "operations"
}

variable "notification_email" {
  description = "Email address to receive cleanup notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds (max 900 seconds / 15 minutes)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB (128-10240 MB)"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression for automated cleanup (cron or rate expression)"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition = can(regex("^(rate\\(\\d+\\s+(minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.schedule_expression))
    error_message = "Schedule expression must be a valid rate() or cron() expression."
  }
}

variable "enable_scheduled_cleanup" {
  description = "Enable automatic scheduled cleanup execution"
  type        = bool
  default     = false
}

variable "cleanup_tag_key" {
  description = "Tag key to identify resources for cleanup"
  type        = string
  default     = "AutoCleanup"
  
  validation {
    condition     = length(var.cleanup_tag_key) > 0 && length(var.cleanup_tag_key) <= 128
    error_message = "Cleanup tag key must be between 1 and 128 characters."
  }
}

variable "cleanup_tag_values" {
  description = "List of tag values that trigger resource cleanup"
  type        = list(string)
  default     = ["true", "True", "TRUE"]
  
  validation {
    condition     = length(var.cleanup_tag_values) > 0
    error_message = "At least one cleanup tag value must be specified."
  }
}

variable "dry_run_mode" {
  description = "Enable dry run mode - identifies resources but doesn't terminate them"
  type        = bool
  default     = false
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention period in days for Lambda function logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.lambda_log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention periods."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9\\s_.:/=+\\-@]*$", k))
    ])
    error_message = "Tag keys must contain only alphanumeric characters, spaces, and the characters _.:/=+-@."
  }
}