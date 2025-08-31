# ==============================================================================
# TERRAFORM VARIABLES FOR DAILY STATUS REPORTS INFRASTRUCTURE
# ==============================================================================
# This file defines all configurable parameters for the daily status reports
# solution, including GCP project settings, email configuration, and
# scheduling parameters.

# ==============================================================================
# CORE PROJECT CONFIGURATION
# ==============================================================================

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for deploying resources (e.g., us-central1, europe-west1)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "environment" {
  description = "Environment label for resource tagging (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# ==============================================================================
# RESOURCE NAMING CONFIGURATION
# ==============================================================================

variable "function_name" {
  description = "Base name for the Cloud Function (will have random suffix appended)"
  type        = string
  default     = "daily-status-report"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.function_name))
    error_message = "Function name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "service_account_name" {
  description = "Base name for the service account (will have random suffix appended)"
  type        = string
  default     = "status-reporter"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "job_name" {
  description = "Base name for the Cloud Scheduler job (will have random suffix appended)"
  type        = string
  default     = "daily-report-trigger"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.job_name))
    error_message = "Job name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# ==============================================================================
# EMAIL CONFIGURATION
# ==============================================================================

variable "sender_email" {
  description = "Gmail address that will send the status reports (must have app password configured)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sender_email))
    error_message = "Sender email must be a valid email address format."
  }
}

variable "sender_password" {
  description = "Gmail app password for the sender email account (not the regular password)"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.sender_password) >= 8
    error_message = "Sender password must be at least 8 characters long."
  }
}

variable "recipient_email" {
  description = "Email address that will receive the daily status reports"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.recipient_email))
    error_message = "Recipient email must be a valid email address format."
  }
}

# ==============================================================================
# SCHEDULING CONFIGURATION
# ==============================================================================

variable "cron_schedule" {
  description = "Cron schedule for daily report generation (default: 9 AM UTC daily)"
  type        = string
  default     = "0 9 * * *"
  
  validation {
    condition = can(regex("^[0-9*,-/ ]+$", var.cron_schedule))
    error_message = "Cron schedule must be a valid cron expression (e.g., '0 9 * * *' for daily at 9 AM)."
  }
}

variable "timezone" {
  description = "Timezone for the scheduled job execution (IANA timezone format)"
  type        = string
  default     = "UTC"
  
  validation {
    condition = contains([
      "UTC", "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles",
      "Europe/London", "Europe/Paris", "Europe/Berlin", "Asia/Tokyo", "Asia/Shanghai",
      "Australia/Sydney", "Pacific/Auckland"
    ], var.timezone)
    error_message = "Timezone must be a valid IANA timezone (e.g., UTC, America/New_York, Europe/London)."
  }
}

# ==============================================================================
# CLOUD FUNCTION CONFIGURATION
# ==============================================================================

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, or 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function execution in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

# ==============================================================================
# MONITORING AND REPORTING CONFIGURATION
# ==============================================================================

variable "monitoring_period_hours" {
  description = "Number of hours to look back for monitoring data collection"
  type        = number
  default     = 24
  
  validation {
    condition     = var.monitoring_period_hours >= 1 && var.monitoring_period_hours <= 168
    error_message = "Monitoring period must be between 1 and 168 hours (1 week)."
  }
}

variable "include_cost_analysis" {
  description = "Whether to include basic cost analysis in the status reports"
  type        = bool
  default     = false
}

variable "include_security_insights" {
  description = "Whether to include basic security insights in the status reports"
  type        = bool
  default     = false
}

# ==============================================================================
# ADVANCED CONFIGURATION
# ==============================================================================

variable "enable_vpc_connector" {
  description = "Whether to use VPC Connector for the Cloud Function (required for private resource access)"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of the VPC Connector to use (only used if enable_vpc_connector is true)"
  type        = string
  default     = ""
  
  validation {
    condition = var.enable_vpc_connector == false || (var.enable_vpc_connector == true && length(var.vpc_connector_name) > 0)
    error_message = "VPC Connector name must be provided when enable_vpc_connector is true."
  }
}

variable "max_instances" {
  description = "Maximum number of function instances that can be created"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

# ==============================================================================
# RESOURCE LABELING
# ==============================================================================

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]*$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "cost_center" {
  description = "Cost center identifier for resource billing and tracking"
  type        = string
  default     = ""
}

variable "team_owner" {
  description = "Team or individual responsible for maintaining these resources"
  type        = string
  default     = ""
}