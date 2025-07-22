# Variable Definitions for Secure API Gateway Architecture
# This file defines all input variables with validation and descriptions

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be between 6 and 30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "api_name" {
  description = "Name for the Cloud Endpoints API service"
  type        = string
  default     = "secure-api"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.api_name))
    error_message = "API name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "demo"

  validation {
    condition = contains([
      "dev", "test", "staging", "prod", "demo"
    ], var.environment)
    error_message = "Environment must be one of: dev, test, staging, prod, demo."
  }
}

variable "backend_machine_type" {
  description = "Machine type for backend service instances"
  type        = string
  default     = "e2-medium"

  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.backend_machine_type)
    error_message = "Machine type must be a valid GCP machine type."
  }
}

variable "esp_machine_type" {
  description = "Machine type for Endpoints Service Proxy instances"
  type        = string
  default     = "e2-medium"

  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.esp_machine_type)
    error_message = "Machine type must be a valid GCP machine type."
  }
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold for Cloud Armor (requests per minute per IP)"
  type        = number
  default     = 100

  validation {
    condition     = var.rate_limit_threshold >= 10 && var.rate_limit_threshold <= 10000
    error_message = "Rate limit threshold must be between 10 and 10000 requests per minute."
  }
}

variable "ban_duration_sec" {
  description = "Ban duration in seconds for rate limiting violations"
  type        = number
  default     = 300

  validation {
    condition     = var.ban_duration_sec >= 60 && var.ban_duration_sec <= 3600
    error_message = "Ban duration must be between 60 and 3600 seconds."
  }
}

variable "blocked_countries" {
  description = "List of country codes to block (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["CN", "RU"]

  validation {
    condition = alltrue([
      for country in var.blocked_countries : can(regex("^[A-Z]{2}$", country))
    ])
    error_message = "Country codes must be valid ISO 3166-1 alpha-2 codes (2 uppercase letters)."
  }
}

variable "enable_ssl" {
  description = "Enable SSL/HTTPS termination (requires domain setup)"
  type        = bool
  default     = false
}

variable "custom_domain" {
  description = "Custom domain for the API gateway (requires SSL certificate setup)"
  type        = string
  default     = ""

  validation {
    condition = var.custom_domain == "" || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?([.][a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", var.custom_domain))
    error_message = "Custom domain must be a valid domain name or empty string."
  }
}

variable "backend_port" {
  description = "Port number for backend service"
  type        = number
  default     = 8080

  validation {
    condition     = var.backend_port >= 1 && var.backend_port <= 65535
    error_message = "Backend port must be between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "Health check path for backend services"
  type        = string
  default     = "/health"

  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with a forward slash."
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and logging for resources"
  type        = bool
  default     = true
}

variable "enable_geo_restriction" {
  description = "Enable geographic restriction rules in Cloud Armor"
  type        = bool
  default     = true
}

variable "enable_owasp_protection" {
  description = "Enable OWASP Top 10 protection rules in Cloud Armor"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "secure-api-gateway"
    managed-by  = "terraform"
    environment = "demo"
  }

  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z0-9_-]*$", key)) && can(regex("^[a-z0-9_-]*$", value))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}