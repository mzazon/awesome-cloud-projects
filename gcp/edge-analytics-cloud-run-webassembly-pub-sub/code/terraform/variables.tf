# Input Variables for Edge Analytics Infrastructure
# Variables for configuring GCP resources for IoT edge analytics with WebAssembly and Pub/Sub

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format."
  }
}

variable "zone" {
  description = "Google Cloud zone within the region"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

# Cloud Storage Configuration
variable "storage_location" {
  description = "Location for Cloud Storage bucket (region or multi-region)"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "Storage class for the data lake bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "lifecycle_age_nearline" {
  description = "Number of days after which objects transition to Nearline storage"
  type        = number
  default     = 30
}

variable "lifecycle_age_coldline" {
  description = "Number of days after which objects transition to Coldline storage"
  type        = number
  default     = 90
}

# Pub/Sub Configuration
variable "message_retention_duration" {
  description = "Duration to retain messages in Pub/Sub topic (e.g., '7d', '24h')"
  type        = string
  default     = "7d"
}

variable "subscription_ack_deadline" {
  description = "Maximum time after a subscriber receives a message before the subscriber should acknowledge the message (seconds)"
  type        = number
  default     = 60
  
  validation {
    condition     = var.subscription_ack_deadline >= 10 && var.subscription_ack_deadline <= 600
    error_message = "Ack deadline must be between 10 and 600 seconds."
  }
}

variable "max_retry_delay" {
  description = "Maximum delay between consecutive deliveries of a given message (seconds)"
  type        = number
  default     = 600
}

variable "min_retry_delay" {
  description = "Minimum delay between consecutive deliveries of a given message (seconds)"
  type        = number
  default     = 10
}

# Cloud Run Configuration
variable "cloud_run_memory" {
  description = "Amount of memory allocated to Cloud Run service"
  type        = string
  default     = "1Gi"
  
  validation {
    condition = can(regex("^[0-9]+(Mi|Gi)$", var.cloud_run_memory))
    error_message = "Memory must be specified in Mi or Gi (e.g., 512Mi, 1Gi)."
  }
}

variable "cloud_run_cpu" {
  description = "Number of CPUs allocated to Cloud Run service"
  type        = string
  default     = "2"
  
  validation {
    condition = contains(["1", "2", "4", "8"], var.cloud_run_cpu)
    error_message = "CPU must be one of: 1, 2, 4, 8."
  }
}

variable "cloud_run_concurrency" {
  description = "Maximum number of concurrent requests per Cloud Run instance"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cloud_run_concurrency >= 1 && var.cloud_run_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 100
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
}

variable "cloud_run_timeout" {
  description = "Request timeout for Cloud Run service (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.cloud_run_timeout >= 1 && var.cloud_run_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

# Container Image Configuration
variable "container_image" {
  description = "Container image for Cloud Run service. If empty, a placeholder image will be used."
  type        = string
  default     = ""
}

# Firestore Configuration
variable "firestore_location" {
  description = "Location for Firestore database"
  type        = string
  default     = "us-central"
}

variable "firestore_type" {
  description = "Type of Firestore database"
  type        = string
  default     = "FIRESTORE_NATIVE"
  
  validation {
    condition = contains([
      "FIRESTORE_NATIVE", "DATASTORE_MODE"
    ], var.firestore_type)
    error_message = "Firestore type must be either FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

# Monitoring Configuration
variable "enable_monitoring_alerts" {
  description = "Whether to create Cloud Monitoring alert policies"
  type        = bool
  default     = true
}

variable "anomaly_threshold" {
  description = "Threshold for anomaly detection alerts (anomalies per minute)"
  type        = number
  default     = 5
}

variable "alert_duration" {
  description = "Duration for alert conditions (e.g., '300s')"
  type        = string
  default     = "300s"
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

# IAM Configuration
variable "enable_cloud_run_all_users" {
  description = "Whether to allow unauthenticated access to Cloud Run service"
  type        = bool
  default     = true
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "edge-analytics"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix)) && length(var.resource_prefix) <= 20
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, end with alphanumeric character, and be max 20 characters."
  }
}

variable "use_random_suffix" {
  description = "Whether to append a random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}

# Logging Configuration
variable "log_retention_days" {
  description = "Number of days to retain Cloud Run logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Security Configuration
variable "enable_binary_authorization" {
  description = "Whether to enable Binary Authorization for container images"
  type        = bool
  default     = false
}

variable "ingress" {
  description = "Ingress configuration for Cloud Run service"
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
  
  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    ], var.ingress)
    error_message = "Ingress must be one of: INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

# Cost Optimization
variable "enable_lifecycle_management" {
  description = "Whether to enable lifecycle management for Cloud Storage"
  type        = bool
  default     = true
}

variable "enable_versioning" {
  description = "Whether to enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by = "terraform"
    component  = "edge-analytics"
  }
}