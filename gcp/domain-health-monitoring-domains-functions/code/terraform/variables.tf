# Variables for GCP Domain Health Monitoring Infrastructure

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string

  validation {
    condition     = length(var.project_id) > 0 && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be between 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "domains_to_monitor" {
  description = "List of domains to monitor for health checks"
  type        = list(string)
  default     = ["example.com", "google.com"]

  validation {
    condition     = length(var.domains_to_monitor) > 0
    error_message = "At least one domain must be specified for monitoring."
  }
}

variable "monitoring_schedule" {
  description = "Cron expression for monitoring frequency (default: every 6 hours)"
  type        = string
  default     = "0 */6 * * *"

  validation {
    condition     = can(regex("^[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+\\s+[0-9*,-/]+$", var.monitoring_schedule))
    error_message = "Monitoring schedule must be a valid cron expression."
  }
}

variable "ssl_expiry_warning_days" {
  description = "Number of days before SSL certificate expiry to trigger warnings"
  type        = number
  default     = 30

  validation {
    condition     = var.ssl_expiry_warning_days > 0 && var.ssl_expiry_warning_days <= 365
    error_message = "SSL expiry warning days must be between 1 and 365."
  }
}

variable "function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = string
  default     = "512Mi"

  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "notification_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = ""

  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "enable_cloud_scheduler" {
  description = "Whether to enable automatic scheduling of domain health checks"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"

  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "retention_days" {
  description = "Number of days to retain monitoring results in Cloud Storage"
  type        = number
  default     = 90

  validation {
    condition     = var.retention_days > 0 && var.retention_days <= 3650
    error_message = "Retention days must be between 1 and 3650 (10 years)."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "domain-health-monitoring"
    environment = "production"
    managed-by  = "terraform"
  }

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_private_network" {
  description = "Whether to deploy the Cloud Function in a private network"
  type        = bool
  default     = false
}

variable "vpc_network_name" {
  description = "Name of the VPC network for private Cloud Function deployment"
  type        = string
  default     = "default"
}

variable "vpc_subnet_name" {
  description = "Name of the VPC subnet for private Cloud Function deployment"
  type        = string
  default     = "default"
}