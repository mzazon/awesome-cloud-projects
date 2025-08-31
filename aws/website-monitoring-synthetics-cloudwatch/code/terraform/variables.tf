# Variables for website monitoring infrastructure

variable "website_url" {
  description = "The URL of the website to monitor"
  type        = string
  default     = "https://example.com"
  
  validation {
    condition     = can(regex("^https?://", var.website_url))
    error_message = "Website URL must start with http:// or https://."
  }
}

variable "notification_email" {
  description = "Email address for monitoring alerts"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address."
  }
}

variable "canary_schedule" {
  description = "CloudWatch Synthetics canary schedule expression"
  type        = string
  default     = "rate(5 minutes)"
  
  validation {
    condition     = can(regex("^rate\\([0-9]+\\s+(minute|minutes|hour|hours|day|days)\\)$", var.canary_schedule))
    error_message = "Schedule must be in the format 'rate(X minutes/hours/days)'."
  }
}

variable "canary_timeout" {
  description = "Timeout for canary execution in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.canary_timeout >= 3 && var.canary_timeout <= 840
    error_message = "Canary timeout must be between 3 and 840 seconds."
  }
}

variable "canary_memory" {
  description = "Memory allocation for canary in MB"
  type        = number
  default     = 960
  
  validation {
    condition     = contains([960, 1024, 1536, 2048, 3008], var.canary_memory)
    error_message = "Canary memory must be one of: 960, 1024, 1536, 2048, or 3008 MB."
  }
}

variable "success_retention_days" {
  description = "Number of days to retain successful canary run data"
  type        = number
  default     = 31
  
  validation {
    condition     = var.success_retention_days >= 1 && var.success_retention_days <= 455
    error_message = "Success retention days must be between 1 and 455."
  }
}

variable "failure_retention_days" {
  description = "Number of days to retain failed canary run data"
  type        = number
  default     = 31
  
  validation {
    condition     = var.failure_retention_days >= 1 && var.failure_retention_days <= 455
    error_message = "Failure retention days must be between 1 and 455."
  }
}

variable "success_threshold" {
  description = "Success percentage threshold for failure alarm (below this triggers alarm)"
  type        = number
  default     = 90
  
  validation {
    condition     = var.success_threshold >= 0 && var.success_threshold <= 100
    error_message = "Success threshold must be between 0 and 100."
  }
}

variable "response_time_threshold" {
  description = "Response time threshold in milliseconds for performance alarm"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.response_time_threshold > 0
    error_message = "Response time threshold must be greater than 0."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for alarm conditions"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "Alarm evaluation periods must be at least 1."
  }
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning S3 objects to Standard-IA"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_transition_days >= 1
    error_message = "S3 lifecycle transition days must be at least 1."
  }
}

variable "s3_lifecycle_expiration_days" {
  description = "Number of days before expiring S3 objects"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_lifecycle_expiration_days > var.s3_lifecycle_transition_days
    error_message = "S3 expiration days must be greater than transition days."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "website-monitoring"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_x_ray_tracing" {
  description = "Enable AWS X-Ray tracing for the canary"
  type        = bool
  default     = true
}

variable "create_dashboard" {
  description = "Whether to create a CloudWatch dashboard"
  type        = bool
  default     = true
}

variable "runtime_version" {
  description = "Runtime version for the synthetics canary"
  type        = string
  default     = "syn-nodejs-puppeteer-10.0"
  
  validation {
    condition     = can(regex("^syn-", var.runtime_version))
    error_message = "Runtime version must start with 'syn-'."
  }
}