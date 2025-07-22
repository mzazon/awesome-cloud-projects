# Variables for GCP Domain and Certificate Lifecycle Management
# Recipe: Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "domain_name" {
  description = "The domain name for certificate and DNS management (e.g., example.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain format without protocol or trailing slash."
  }
}

variable "dns_zone_name" {
  description = "Name for the Cloud DNS zone (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "certificate_name" {
  description = "Name for the SSL certificate (will be auto-generated if not provided)"
  type        = string
  default     = ""
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for certificate and DNS health checks"
  type        = bool
  default     = true
}

variable "monitoring_schedule" {
  description = "Cron schedule for certificate monitoring (Cloud Scheduler format)"
  type        = string
  default     = "0 */6 * * *"  # Every 6 hours
  validation {
    condition     = can(regex("^[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+$", var.monitoring_schedule))
    error_message = "Monitoring schedule must be a valid cron expression (5 fields)."
  }
}

variable "daily_audit_schedule" {
  description = "Cron schedule for daily comprehensive certificate audit"
  type        = string
  default     = "0 2 * * *"  # Daily at 2:00 AM UTC
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.function_timeout >= 10 && var.function_timeout <= 540
    error_message = "Function timeout must be between 10 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 256
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "create_load_balancer" {
  description = "Create Application Load Balancer for demonstration"
  type        = bool
  default     = true
}

variable "dns_ttl" {
  description = "TTL for DNS records in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.dns_ttl >= 30 && var.dns_ttl <= 86400
    error_message = "DNS TTL must be between 30 and 86400 seconds."
  }
}

variable "enable_www_subdomain" {
  description = "Create www subdomain CNAME record"
  type        = bool
  default     = true
}

variable "certificate_domains" {
  description = "Additional domains to include in the certificate (beyond the primary domain)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for domain in var.certificate_domains : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.[a-z]{2,}$", domain))
    ])
    error_message = "All certificate domains must be valid domain formats."
  }
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor security policy for the load balancer"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "certificate-automation"
    managed-by  = "terraform"
    recipe      = "domain-certificate-lifecycle-dns-manager"
  }
}

variable "service_account_name" {
  description = "Name for the service account used by automation functions"
  type        = string
  default     = "cert-automation"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_apis" {
  description = "Enable required Google Cloud APIs"
  type        = bool
  default     = true
}