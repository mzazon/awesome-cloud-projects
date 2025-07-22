# Variables for zero-trust network security infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be a valid GCP project ID format (6-30 characters, lowercase letters, numbers, and hyphens)."
  }
}

variable "project_number" {
  description = "The GCP project number (required for IAP configuration)"
  type        = string
  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "Project number must be numeric."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-southeast1", "asia-southeast2", "asia-south1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = ""
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "zero-trust-vpc"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.network_name))
    error_message = "Network name must be valid: lowercase, start with letter, can contain hyphens."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.1.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "zero-trust-app"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.application_name))
    error_message = "Application name must be valid: lowercase, start with letter, can contain hyphens."
  }
}

# Cloud Armor Configuration
variable "security_policy_name" {
  description = "Name of the Cloud Armor security policy"
  type        = string
  default     = "zero-trust-armor-policy"
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold (requests per minute per IP)"
  type        = number
  default     = 100
  validation {
    condition     = var.rate_limit_threshold > 0 && var.rate_limit_threshold <= 10000
    error_message = "Rate limit threshold must be between 1 and 10000."
  }
}

variable "ban_duration_sec" {
  description = "Duration in seconds to ban IPs that exceed rate limits"
  type        = number
  default     = 300
  validation {
    condition     = var.ban_duration_sec >= 60 && var.ban_duration_sec <= 86400
    error_message = "Ban duration must be between 60 and 86400 seconds (1 minute to 24 hours)."
  }
}

variable "blocked_countries" {
  description = "List of country codes to block (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["CN", "RU", "KP"]
  validation {
    condition = alltrue([
      for country in var.blocked_countries : can(regex("^[A-Z]{2}$", country))
    ])
    error_message = "Country codes must be valid ISO 3166-1 alpha-2 format (e.g., 'US', 'CN')."
  }
}

# Backend Configuration
variable "backend_instance_count" {
  description = "Number of backend instances in the managed instance group"
  type        = number
  default     = 2
  validation {
    condition     = var.backend_instance_count >= 1 && var.backend_instance_count <= 10
    error_message = "Backend instance count must be between 1 and 10."
  }
}

variable "machine_type" {
  description = "Machine type for backend instances"
  type        = string
  default     = "e2-medium"
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n2-standard-2", "n2-standard-4", "n2-standard-8",
      "c2-standard-4", "c2-standard-8"
    ], var.machine_type)
    error_message = "Machine type must be a valid GCE machine type."
  }
}

# Service Extension Configuration
variable "service_extension_name" {
  description = "Name of the Cloud Run service extension"
  type        = string
  default     = "zero-trust-extension"
}

variable "service_extension_image" {
  description = "Container image for the service extension"
  type        = string
  default     = "gcr.io/cloudrun/hello" # Default to hello service for testing
}

variable "service_extension_cpu" {
  description = "CPU allocation for service extension"
  type        = string
  default     = "1"
  validation {
    condition = contains(["0.08", "0.17", "0.25", "0.5", "1", "2", "4", "6", "8"], var.service_extension_cpu)
    error_message = "CPU must be a valid Cloud Run CPU allocation."
  }
}

variable "service_extension_memory" {
  description = "Memory allocation for service extension"
  type        = string
  default     = "512Mi"
  validation {
    condition = can(regex("^[0-9]+(Mi|Gi)$", var.service_extension_memory))
    error_message = "Memory must be specified in Mi or Gi format (e.g., 512Mi, 2Gi)."
  }
}

# IAP Configuration
variable "oauth_client_id" {
  description = "OAuth 2.0 client ID for IAP"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oauth_client_secret" {
  description = "OAuth 2.0 client secret for IAP"
  type        = string
  default     = ""
  sensitive   = true
}

variable "iap_domain" {
  description = "Domain for IAP access (e.g., yourdomain.com)"
  type        = string
  default     = "example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$", var.iap_domain))
    error_message = "IAP domain must be a valid domain name."
  }
}

variable "iap_users" {
  description = "List of users to grant IAP access (email addresses)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.iap_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All IAP users must be valid email addresses."
  }
}

# SSL Certificate Configuration
variable "ssl_domains" {
  description = "List of domains for the managed SSL certificate"
  type        = list(string)
  default     = ["app.example.com"]
  validation {
    condition = alltrue([
      for domain in var.ssl_domains : can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$", domain))
    ])
    error_message = "All SSL domains must be valid domain names."
  }
}

# Monitoring Configuration
variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = "admin@example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain security logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
}

# Network Security Configuration
variable "enable_flow_logs" {
  description = "Enable VPC flow logs for network monitoring"
  type        = bool
  default     = true
}

variable "enable_private_google_access" {
  description = "Enable private Google access for instances without external IPs"
  type        = bool
  default     = true
}

# Tags for resource organization
variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    purpose    = "zero-trust-security"
  }
}

# Advanced Security Options
variable "enable_shielded_vm" {
  description = "Enable Shielded VM features for backend instances"
  type        = bool
  default     = true
}

variable "enable_confidential_compute" {
  description = "Enable Confidential Computing for backend instances"
  type        = bool
  default     = false
}

variable "enable_adaptive_protection" {
  description = "Enable Cloud Armor adaptive protection (DDoS defense)"
  type        = bool
  default     = true
}

# Resource naming prefix
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = ""
  validation {
    condition     = var.resource_prefix == "" || can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.resource_prefix))
    error_message = "Resource prefix must be empty or valid: lowercase, start with letter, can contain hyphens."
  }
}