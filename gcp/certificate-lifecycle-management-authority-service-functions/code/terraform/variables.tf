# ==============================================================================
# Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions
# Variable Definitions
# ==============================================================================

# ==============================================================================
# Project and Region Configuration
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id)) || var.project_id == ""
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region where resources will be deployed"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# ==============================================================================
# Certificate Authority Configuration
# ==============================================================================

variable "ca_pool_name" {
  description = "Name for the Certificate Authority pool"
  type        = string
  default     = "enterprise-ca-pool"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{0,62}$", var.ca_pool_name))
    error_message = "CA pool name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "root_ca_name" {
  description = "Name for the root Certificate Authority"
  type        = string
  default     = "root-ca"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{0,62}$", var.root_ca_name))
    error_message = "Root CA name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "sub_ca_name" {
  description = "Name for the subordinate Certificate Authority"
  type        = string
  default     = "sub-ca"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{0,62}$", var.sub_ca_name))
    error_message = "Subordinate CA name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "organization_name" {
  description = "Organization name for certificate subjects"
  type        = string
  default     = "Example Organization"
  
  validation {
    condition = length(var.organization_name) >= 1 && length(var.organization_name) <= 64
    error_message = "Organization name must be between 1 and 64 characters."
  }
}

variable "country_code" {
  description = "Two-letter country code for certificate subjects (ISO 3166-1 alpha-2)"
  type        = string
  default     = "US"
  
  validation {
    condition = can(regex("^[A-Z]{2}$", var.country_code))
    error_message = "Country code must be a valid two-letter ISO 3166-1 alpha-2 code (e.g., US, CA, GB)."
  }
}

variable "root_ca_lifetime_years" {
  description = "Lifetime of the root CA in years"
  type        = number
  default     = 10
  
  validation {
    condition = var.root_ca_lifetime_years >= 5 && var.root_ca_lifetime_years <= 30
    error_message = "Root CA lifetime must be between 5 and 30 years."
  }
}

variable "sub_ca_lifetime_years" {
  description = "Lifetime of the subordinate CA in years"
  type        = number
  default     = 5
  
  validation {
    condition = var.sub_ca_lifetime_years >= 1 && var.sub_ca_lifetime_years <= 10
    error_message = "Subordinate CA lifetime must be between 1 and 10 years."
  }
}

variable "max_cert_lifetime_days" {
  description = "Maximum lifetime for issued certificates in days"
  type        = number
  default     = 365
  
  validation {
    condition = var.max_cert_lifetime_days >= 1 && var.max_cert_lifetime_days <= 1095
    error_message = "Maximum certificate lifetime must be between 1 and 1095 days (3 years)."
  }
}

# ==============================================================================
# Cloud Functions Configuration
# ==============================================================================

variable "monitor_function_name" {
  description = "Name for the certificate monitoring Cloud Function"
  type        = string
  default     = "cert-monitor"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{0,62}$", var.monitor_function_name))
    error_message = "Function name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "renew_function_name" {
  description = "Name for the certificate renewal Cloud Function"
  type        = string
  default     = "cert-renew"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{0,62}$", var.renew_function_name))
    error_message = "Function name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "revoke_function_name" {
  description = "Name for the certificate revocation Cloud Function"
  type        = string
  default     = "cert-revoke"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{0,62}$", var.revoke_function_name))
    error_message = "Function name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "service_account_name" {
  description = "Name for the service account used by Cloud Functions"
  type        = string
  default     = "cert-automation-sa"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# Certificate Management Configuration
# ==============================================================================

variable "renewal_threshold_days" {
  description = "Number of days before expiration to trigger certificate renewal"
  type        = number
  default     = 30
  
  validation {
    condition = var.renewal_threshold_days >= 1 && var.renewal_threshold_days <= 90
    error_message = "Renewal threshold must be between 1 and 90 days."
  }
}

variable "monitoring_schedule" {
  description = "Cron schedule for certificate monitoring (e.g., '0 8 * * *' for daily at 8 AM)"
  type        = string
  default     = "0 8 * * *"
  
  validation {
    condition = can(regex("^[0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+$", var.monitoring_schedule))
    error_message = "Monitoring schedule must be a valid cron expression (5 fields: minute hour day month day-of-week)."
  }
}

variable "time_zone" {
  description = "Time zone for the monitoring schedule (e.g., 'America/New_York', 'UTC')"
  type        = string
  default     = "America/New_York"
  
  validation {
    condition = length(var.time_zone) > 0
    error_message = "Time zone must be a valid IANA time zone identifier."
  }
}

# ==============================================================================
# Cloud Scheduler Configuration
# ==============================================================================

variable "scheduler_job_name" {
  description = "Name for the Cloud Scheduler job"
  type        = string
  default     = "cert-check"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]{0,62}$", var.scheduler_job_name))
    error_message = "Scheduler job name must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# Labeling and Tagging
# ==============================================================================

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = length(var.labels) <= 64
    error_message = "Maximum of 64 labels are allowed per resource."
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter, be 1-63 characters, and contain only lowercase letters, numbers, underscores, and hyphens."
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label values must be 0-63 characters and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# ==============================================================================
# Security and Compliance Configuration
# ==============================================================================

variable "enable_audit_logs" {
  description = "Enable audit logging for Certificate Authority Service operations"
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for certificate lifecycle events"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for channel in var.notification_channels : can(regex("^projects/[^/]+/notificationChannels/[^/]+$", channel))
    ])
    error_message = "Notification channels must be in the format 'projects/{project}/notificationChannels/{channel_id}'."
  }
}

# ==============================================================================
# Function Source Code Configuration
# ==============================================================================

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540
  
  validation {
    condition = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

variable "monitor_function_memory" {
  description = "Memory allocation for the monitoring function"
  type        = string
  default     = "256M"
  
  validation {
    condition = contains(["128M", "256M", "512M", "1G", "2G", "4G", "8G"], var.monitor_function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1G, 2G, 4G, 8G."
  }
}

variable "renewal_function_memory" {
  description = "Memory allocation for the renewal function"
  type        = string
  default     = "512M"
  
  validation {
    condition = contains(["128M", "256M", "512M", "1G", "2G", "4G", "8G"], var.renewal_function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1G, 2G, 4G, 8G."
  }
}

variable "revocation_function_memory" {
  description = "Memory allocation for the revocation function"
  type        = string
  default     = "256M"
  
  validation {
    condition = contains(["128M", "256M", "512M", "1G", "2G", "4G", "8G"], var.revocation_function_memory)
    error_message = "Function memory must be one of: 128M, 256M, 512M, 1G, 2G, 4G, 8G."
  }
}

# ==============================================================================
# Advanced Configuration Options
# ==============================================================================

variable "ca_pool_tier" {
  description = "Tier of the Certificate Authority pool (ENTERPRISE or DEVOPS)"
  type        = string
  default     = "ENTERPRISE"
  
  validation {
    condition = contains(["ENTERPRISE", "DEVOPS"], var.ca_pool_tier)
    error_message = "CA pool tier must be either ENTERPRISE or DEVOPS."
  }
}

variable "enable_crl_distribution" {
  description = "Enable Certificate Revocation List (CRL) distribution"
  type        = bool
  default     = true
}

variable "enable_ca_cert_distribution" {
  description = "Enable CA certificate distribution"
  type        = bool
  default     = true
}

variable "certificate_encoding_format" {
  description = "Encoding format for published certificates and CRLs"
  type        = string
  default     = "PEM"
  
  validation {
    condition = contains(["PEM", "DER"], var.certificate_encoding_format)
    error_message = "Certificate encoding format must be either PEM or DER."
  }
}

variable "max_function_instances" {
  description = "Maximum number of function instances that can run concurrently"
  type        = number
  default     = 10
  
  validation {
    condition = var.max_function_instances >= 1 && var.max_function_instances <= 1000
    error_message = "Maximum function instances must be between 1 and 1000."
  }
}

variable "min_function_instances" {
  description = "Minimum number of function instances to keep warm"
  type        = number
  default     = 0
  
  validation {
    condition = var.min_function_instances >= 0 && var.min_function_instances <= 1000
    error_message = "Minimum function instances must be between 0 and 1000."
  }
}