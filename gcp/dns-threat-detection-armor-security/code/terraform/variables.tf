# Variables for GCP DNS threat detection infrastructure

variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "organization_id" {
  description = "The Google Cloud organization ID for Security Command Center"
  type        = string
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for compute resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "dns-security"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "dns_zone_name" {
  description = "Name for the DNS managed zone"
  type        = string
  default     = "security-demo.example.com."
  
  validation {
    condition = can(regex("^[a-z0-9.-]+\\.$", var.dns_zone_name))
    error_message = "DNS zone name must be a valid FQDN ending with a dot."
  }
}

variable "high_risk_countries" {
  description = "List of country codes to block in Cloud Armor policy"
  type        = list(string)
  default     = ["CN", "RU"]
  
  validation {
    condition = alltrue([for country in var.high_risk_countries : can(regex("^[A-Z]{2}$", country))])
    error_message = "Country codes must be 2-letter uppercase ISO country codes."
  }
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold for DNS queries per minute"
  type        = number
  default     = 100
  
  validation {
    condition = var.rate_limit_threshold > 0 && var.rate_limit_threshold <= 10000
    error_message = "Rate limit threshold must be between 1 and 10000."
  }
}

variable "rate_limit_ban_duration" {
  description = "Ban duration in seconds for rate limiting violations"
  type        = number
  default     = 600
  
  validation {
    condition = var.rate_limit_ban_duration >= 60 && var.rate_limit_ban_duration <= 86400
    error_message = "Ban duration must be between 60 and 86400 seconds (1 minute to 24 hours)."
  }
}

variable "cloud_function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.cloud_function_memory)
    error_message = "Cloud Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "cloud_function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.cloud_function_timeout >= 1 && var.cloud_function_timeout <= 540
    error_message = "Cloud Function timeout must be between 1 and 540 seconds."
  }
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

variable "enable_security_center_premium" {
  description = "Enable Security Command Center Premium tier"
  type        = bool
  default     = true
}

variable "enable_dns_logging" {
  description = "Enable DNS query logging"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for security notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "pubsub_ack_deadline" {
  description = "Pub/Sub subscription acknowledgement deadline in seconds"
  type        = number
  default     = 60
  
  validation {
    condition = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Pub/Sub acknowledgement deadline must be between 10 and 600 seconds."
  }
}

variable "monitoring_alert_threshold" {
  description = "Threshold for malware DNS query alerts"
  type        = number
  default     = 5
  
  validation {
    condition = var.monitoring_alert_threshold > 0 && var.monitoring_alert_threshold <= 100
    error_message = "Monitoring alert threshold must be between 1 and 100."
  }
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor security policies"
  type        = bool
  default     = true
}

variable "enable_automated_response" {
  description = "Enable automated response Cloud Function"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "dns-threat-detection"
    environment = "production"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for key, value in var.labels : 
      can(regex("^[a-z][a-z0-9_-]{0,62}$", key)) && 
      can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "Labels must follow Google Cloud label requirements."
  }
}