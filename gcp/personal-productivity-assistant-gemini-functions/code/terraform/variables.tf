# Variables for GCP Personal Productivity Assistant with Gemini and Functions
# Terraform Infrastructure Configuration

# Project Configuration
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid Google Cloud region identifier."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone identifier."
  }
}

# Environment Configuration
variable "environment" {
  description = "Environment name for resource labeling and identification"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# Cloud Scheduler Configuration
variable "schedule_cron" {
  description = "Cron expression for automated email processing schedule"
  type        = string
  default     = "*/15 8-18 * * 1-5"
  
  validation {
    condition     = can(regex("^[0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+\\s+[0-9*/,-]+$", var.schedule_cron))
    error_message = "Schedule must be a valid cron expression (minute hour day month weekday)."
  }
}

variable "schedule_timezone" {
  description = "Timezone for the scheduled email processing (IANA timezone format)"
  type        = string
  default     = "America/New_York"
  
  validation {
    condition     = can(regex("^[A-Za-z]+/[A-Za-z_]+$", var.schedule_timezone))
    error_message = "Timezone must be a valid IANA timezone identifier (e.g., America/New_York)."
  }
}

# Cloud Function Configuration
variable "email_processor_memory" {
  description = "Memory allocation for the email processing function (in MB)"
  type        = number
  default     = 1024
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.email_processor_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "email_processor_timeout" {
  description = "Timeout for the email processing function (in seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.email_processor_timeout >= 60 && var.email_processor_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "scheduled_processor_memory" {
  description = "Memory allocation for the scheduled processing function (in MB)"
  type        = number
  default     = 512
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.scheduled_processor_memory)
    error_message = "Memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "scheduled_processor_timeout" {
  description = "Timeout for the scheduled processing function (in seconds)"
  type        = number
  default     = 180
  
  validation {
    condition     = var.scheduled_processor_timeout >= 60 && var.scheduled_processor_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "max_function_instances" {
  description = "Maximum number of concurrent function instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_function_instances >= 1 && var.max_function_instances <= 1000
    error_message = "Maximum function instances must be between 1 and 1000."
  }
}

variable "min_function_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_function_instances >= 0 && var.min_function_instances <= 100
    error_message = "Minimum function instances must be between 0 and 100."
  }
}

# Pub/Sub Configuration
variable "message_retention_duration" {
  description = "Message retention duration for Pub/Sub topics (in seconds)"
  type        = string
  default     = "604800s"
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention_duration))
    error_message = "Message retention duration must be specified in seconds with 's' suffix (e.g., '604800s')."
  }
}

variable "subscription_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub subscription (in seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.subscription_ack_deadline >= 10 && var.subscription_ack_deadline <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "max_delivery_attempts" {
  description = "Maximum delivery attempts before sending message to dead letter queue"
  type        = number
  default     = 5
  
  validation {
    condition     = var.max_delivery_attempts >= 3 && var.max_delivery_attempts <= 100
    error_message = "Maximum delivery attempts must be between 3 and 100."
  }
}

# Firestore Configuration
variable "firestore_location" {
  description = "Location for Firestore database (if different from region)"
  type        = string
  default     = ""
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for Firestore database"
  type        = bool
  default     = true
}

# Security Configuration
variable "allow_unauthenticated_access" {
  description = "Allow unauthenticated access to the email processing function"
  type        = bool
  default     = false
}

variable "enable_security_policy" {
  description = "Enable Cloud Armor security policy for enhanced protection"
  type        = bool
  default     = false
}

variable "rate_limit_requests_per_minute" {
  description = "Rate limit for requests per minute per IP address"
  type        = number
  default     = 60
  
  validation {
    condition     = var.rate_limit_requests_per_minute >= 10 && var.rate_limit_requests_per_minute <= 1000
    error_message = "Rate limit must be between 10 and 1000 requests per minute."
  }
}

variable "rate_limit_ban_duration" {
  description = "Ban duration for rate limiting violations (in seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.rate_limit_ban_duration >= 60 && var.rate_limit_ban_duration <= 3600
    error_message = "Ban duration must be between 60 and 3600 seconds."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring dashboards and alerts"
  type        = bool
  default     = true
}

variable "error_rate_threshold" {
  description = "Error rate threshold for monitoring alerts (as decimal, e.g., 0.1 for 10%)"
  type        = number
  default     = 0.1
  
  validation {
    condition     = var.error_rate_threshold >= 0.01 && var.error_rate_threshold <= 1.0
    error_message = "Error rate threshold must be between 0.01 (1%) and 1.0 (100%)."
  }
}

variable "alert_notification_period" {
  description = "Minimum period between alert notifications (in seconds)"
  type        = string
  default     = "300s"
  
  validation {
    condition     = can(regex("^[0-9]+s$", var.alert_notification_period))
    error_message = "Notification period must be specified in seconds with 's' suffix (e.g., '300s')."
  }
}

# Storage Configuration
variable "function_source_bucket_lifecycle_age" {
  description = "Age in days after which function source objects are deleted"
  type        = number
  default     = 30
  
  validation {
    condition     = var.function_source_bucket_lifecycle_age >= 7 && var.function_source_bucket_lifecycle_age <= 365
    error_message = "Lifecycle age must be between 7 and 365 days."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for the function source bucket"
  type        = bool
  default     = true
}

# Gmail API Configuration
variable "gmail_api_scopes" {
  description = "OAuth scopes required for Gmail API access"
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.modify"
  ]
  
  validation {
    condition = alltrue([
      for scope in var.gmail_api_scopes : can(regex("^https://www\\.googleapis\\.com/auth/", scope))
    ])
    error_message = "All scopes must be valid Google API OAuth scopes starting with 'https://www.googleapis.com/auth/'."
  }
}

# Vertex AI Configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI services (if different from main region)"
  type        = string
  default     = ""
}

variable "gemini_model_name" {
  description = "Gemini model name for email processing"
  type        = string
  default     = "gemini-2.5-flash-002"
  
  validation {
    condition     = can(regex("^gemini-", var.gemini_model_name))
    error_message = "Model name must be a valid Gemini model identifier."
  }
}

variable "gemini_temperature" {
  description = "Temperature setting for Gemini model responses (0.0 to 1.0)"
  type        = number
  default     = 0.3
  
  validation {
    condition     = var.gemini_temperature >= 0.0 && var.gemini_temperature <= 1.0
    error_message = "Temperature must be between 0.0 and 1.0."
  }
}

variable "gemini_top_p" {
  description = "Top-p setting for Gemini model responses (0.0 to 1.0)"
  type        = number
  default     = 0.8
  
  validation {
    condition     = var.gemini_top_p >= 0.0 && var.gemini_top_p <= 1.0
    error_message = "Top-p must be between 0.0 and 1.0."
  }
}

variable "gemini_max_output_tokens" {
  description = "Maximum output tokens for Gemini model responses"
  type        = number
  default     = 2048
  
  validation {
    condition     = var.gemini_max_output_tokens >= 256 && var.gemini_max_output_tokens <= 8192
    error_message = "Maximum output tokens must be between 256 and 8192."
  }
}

# Resource Labeling
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for key, value in var.additional_labels : can(regex("^[a-z0-9_-]+$", key)) && can(regex("^[a-z0-9_-]+$", value))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost Management
variable "enable_cost_controls" {
  description = "Enable cost control features like function scaling limits"
  type        = bool
  default     = true
}

variable "daily_function_invocation_limit" {
  description = "Daily limit for function invocations (for cost control)"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.daily_function_invocation_limit >= 100 && var.daily_function_invocation_limit <= 100000
    error_message = "Daily invocation limit must be between 100 and 100,000."
  }
}

# Development and Testing
variable "enable_debug_logging" {
  description = "Enable debug-level logging for troubleshooting"
  type        = bool
  default     = false
}

variable "function_source_path" {
  description = "Path to local function source code (for development)"
  type        = string
  default     = "./function-source"
}

# Backup and Disaster Recovery
variable "enable_backup_schedule" {
  description = "Enable automated backup schedule for Firestore"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 7 and 365 days."
  }
}