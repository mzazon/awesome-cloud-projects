# Project and region configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "primary_region" {
  description = "Primary region for deployment (US region)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "us-east4", "us-west3", "us-west4"
    ], var.primary_region)
    error_message = "Primary region must be a valid US region."
  }
}

variable "secondary_region" {
  description = "Secondary region for deployment (EU region)"
  type        = string
  default     = "europe-west1"
  validation {
    condition = contains([
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "europe-north1", "europe-central2"
    ], var.secondary_region)
    error_message = "Secondary region must be a valid EU region."
  }
}

# Network configuration
variable "network_name" {
  description = "Name of the VPC network for Apigee deployment"
  type        = string
  default     = "apigee-network"
  validation {
    condition     = can(regex("^[a-z][-a-z0-9]*[a-z0-9]$", var.network_name))
    error_message = "Network name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "primary_subnet_cidr" {
  description = "CIDR block for the primary region subnet"
  type        = string
  default     = "10.1.0.0/16"
  validation {
    condition     = can(cidrhost(var.primary_subnet_cidr, 0))
    error_message = "Primary subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_subnet_cidr" {
  description = "CIDR block for the secondary region subnet"
  type        = string
  default     = "10.2.0.0/16"
  validation {
    condition     = can(cidrhost(var.secondary_subnet_cidr, 0))
    error_message = "Secondary subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# Apigee configuration
variable "apigee_billing_type" {
  description = "Billing type for Apigee organization (EVALUATION or PAYG)"
  type        = string
  default     = "PAYG"
  validation {
    condition     = contains(["EVALUATION", "PAYG"], var.apigee_billing_type)
    error_message = "Apigee billing type must be either EVALUATION or PAYG."
  }
}

variable "apigee_runtime_type" {
  description = "Runtime type for Apigee organization"
  type        = string
  default     = "CLOUD"
  validation {
    condition     = contains(["CLOUD", "HYBRID"], var.apigee_runtime_type)
    error_message = "Apigee runtime type must be either CLOUD or HYBRID."
  }
}

# Domain and SSL configuration
variable "domain_names" {
  description = "List of domain names for SSL certificate"
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.domain_names) <= 100
    error_message = "Cannot specify more than 100 domain names for SSL certificate."
  }
}

# Cloud Armor configuration
variable "blocked_regions" {
  description = "List of region codes to block in Cloud Armor policy"
  type        = list(string)
  default     = ["CN", "RU"]
  validation {
    condition     = length(var.blocked_regions) <= 50
    error_message = "Cannot block more than 50 regions."
  }
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold for DDoS protection (requests per minute)"
  type        = number
  default     = 100
  validation {
    condition     = var.rate_limit_threshold > 0 && var.rate_limit_threshold <= 10000
    error_message = "Rate limit threshold must be between 1 and 10000."
  }
}

variable "ban_duration_seconds" {
  description = "Duration in seconds to ban clients exceeding rate limits"
  type        = number
  default     = 600
  validation {
    condition     = var.ban_duration_seconds >= 60 && var.ban_duration_seconds <= 3600
    error_message = "Ban duration must be between 60 and 3600 seconds."
  }
}

# Resource naming and tagging
variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_suffix))
    error_message = "Resource suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "production"
    project     = "api-security"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Health check configuration
variable "health_check_path" {
  description = "Path for health check endpoint"
  type        = string
  default     = "/health"
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "health_check_port" {
  description = "Port for health check"
  type        = number
  default     = 80
  validation {
    condition     = var.health_check_port > 0 && var.health_check_port <= 65535
    error_message = "Health check port must be between 1 and 65535."
  }
}

# Security and compliance settings
variable "enable_cloud_armor_logging" {
  description = "Enable verbose logging for Cloud Armor security policy"
  type        = bool
  default     = true
}

variable "enable_ssl_redirect" {
  description = "Enable automatic redirect from HTTP to HTTPS"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version for SSL policy"
  type        = string
  default     = "TLS_1_2"
  validation {
    condition     = contains(["TLS_1_0", "TLS_1_1", "TLS_1_2", "TLS_1_3"], var.minimum_tls_version)
    error_message = "Minimum TLS version must be one of: TLS_1_0, TLS_1_1, TLS_1_2, TLS_1_3."
  }
}