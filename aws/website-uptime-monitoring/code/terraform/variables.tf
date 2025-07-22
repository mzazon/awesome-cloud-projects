# ==============================================================================
# Variables for Website Uptime Monitoring with Route 53 Health Checks
# ==============================================================================
# This file defines input variables for configuring the uptime monitoring
# solution with appropriate validation and default values.

# ==============================================================================
# Project Configuration
# ==============================================================================

variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "website-monitor"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only alphanumeric characters and hyphens, and end with an alphanumeric character."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Environment   = "production"
    Owner         = "devops"
    ManagedBy     = "terraform"
    Project       = "uptime-monitoring"
  }
}

# ==============================================================================
# Website Monitoring Configuration
# ==============================================================================

variable "website_url" {
  description = "The complete URL of the website to monitor (including protocol)"
  type        = string
  default     = "https://httpbin.org/status/200"

  validation {
    condition     = can(regex("^https?://[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\\.[a-zA-Z]{2,}(\\.[a-zA-Z]{2,})?(/.*)?$", var.website_url))
    error_message = "Website URL must be a valid HTTP or HTTPS URL with a proper domain name."
  }
}

variable "website_url_scheme" {
  description = "The protocol scheme of the website URL (http or https)"
  type        = string
  default     = "https"

  validation {
    condition     = contains(["http", "https"], var.website_url_scheme)
    error_message = "Website URL scheme must be either 'http' or 'https'."
  }
}

variable "health_check_path" {
  description = "The path to check on the website (e.g., /health, /status)"
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with a forward slash (/)."
  }
}

variable "search_string" {
  description = "Optional string to search for in the response body for more reliable health checks"
  type        = string
  default     = ""

  validation {
    condition     = length(var.search_string) <= 255
    error_message = "Search string must be 255 characters or less."
  }
}

# ==============================================================================
# Route 53 Health Check Configuration
# ==============================================================================

variable "failure_threshold" {
  description = "Number of consecutive health check failures required before considering the endpoint unhealthy"
  type        = number
  default     = 3

  validation {
    condition     = var.failure_threshold >= 1 && var.failure_threshold <= 10
    error_message = "Failure threshold must be between 1 and 10."
  }
}

variable "request_interval" {
  description = "The number of seconds between health checks (30 or 10)"
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.request_interval)
    error_message = "Request interval must be either 10 or 30 seconds."
  }
}

variable "health_check_regions" {
  description = "List of AWS regions from which to perform health checks"
  type        = list(string)
  default = [
    "us-east-1",
    "us-west-1", 
    "us-west-2",
    "eu-west-1",
    "ap-southeast-1",
    "ap-southeast-2"
  ]

  validation {
    condition = alltrue([
      for region in var.health_check_regions : 
      can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", region))
    ])
    error_message = "All health check regions must be valid AWS region identifiers (e.g., us-east-1, eu-west-1)."
  }

  validation {
    condition     = length(var.health_check_regions) >= 3 && length(var.health_check_regions) <= 18
    error_message = "Must specify between 3 and 18 health check regions for reliable monitoring."
  }
}

# ==============================================================================
# CloudWatch Alarm Configuration
# ==============================================================================

variable "alarm_evaluation_periods" {
  description = "Number of periods over which to evaluate the alarm"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 5
    error_message = "Alarm evaluation periods must be between 1 and 5."
  }
}

variable "health_percentage_threshold" {
  description = "Minimum percentage of health checkers that must report healthy"
  type        = number
  default     = 75

  validation {
    condition     = var.health_percentage_threshold >= 50 && var.health_percentage_threshold <= 100
    error_message = "Health percentage threshold must be between 50 and 100."
  }
}

# ==============================================================================
# Notification Configuration
# ==============================================================================

variable "notification_email" {
  description = "Email address to receive uptime alert notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# ==============================================================================
# Advanced Configuration Options
# ==============================================================================

variable "enable_latency_monitoring" {
  description = "Enable latency monitoring for the health checks"
  type        = bool
  default     = true
}

variable "enable_string_matching" {
  description = "Enable string matching in health check responses"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be one of the supported values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653."
  }
}

# ==============================================================================
# Cost Optimization Settings
# ==============================================================================

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring (additional cost but more granular metrics)"
  type        = bool
  default     = false
}

variable "dashboard_auto_refresh" {
  description = "Auto-refresh interval for CloudWatch dashboard in seconds"
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 300, 900, 3600], var.dashboard_auto_refresh)
    error_message = "Dashboard auto-refresh must be one of: 60 (1 min), 300 (5 min), 900 (15 min), 3600 (1 hour)."
  }
}