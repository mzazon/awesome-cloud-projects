# Project Configuration Variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-southeast1", "asia-east1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for resources"
  type        = string
  default     = "us-central1-a"
}

# Naming Configuration Variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "application_name" {
  description = "Name of the application for resource naming"
  type        = string
  default     = "behavioral-analytics"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.application_name))
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Pub/Sub Configuration Variables
variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic for user events"
  type        = string
  default     = "user-events"
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription for analytics processing"
  type        = string
  default     = "analytics-processor"
}

variable "message_retention_duration" {
  description = "How long to retain unacknowledged messages (seconds)"
  type        = string
  default     = "604800s" # 7 days
}

variable "ack_deadline_seconds" {
  description = "Maximum time after a subscriber receives a message before the subscriber should acknowledge the message"
  type        = number
  default     = 60
  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "Ack deadline must be between 10 and 600 seconds."
  }
}

# Firestore Configuration Variables
variable "firestore_database_name" {
  description = "Name for the Firestore database"
  type        = string
  default     = "behavioral-analytics"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.firestore_database_name))
    error_message = "Firestore database name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "firestore_location" {
  description = "Location for the Firestore database"
  type        = string
  default     = "us-central"
}

# Container Image Configuration Variables
variable "container_image" {
  description = "Container image for the behavioral analytics processor"
  type        = string
  default     = "gcr.io/cloudrun/hello" # Default image, should be replaced with actual image
}

variable "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository for container images"
  type        = string
  default     = "behavioral-analytics"
}

# Cloud Run Worker Pool Configuration Variables
variable "worker_pool_name" {
  description = "Name for the Cloud Run worker pool"
  type        = string
  default     = "behavioral-processor"
}

variable "worker_pool_memory" {
  description = "Memory allocation for worker pool containers"
  type        = string
  default     = "1Gi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi", "16Gi", "32Gi"
    ], var.worker_pool_memory)
    error_message = "Memory must be a valid Cloud Run memory allocation."
  }
}

variable "worker_pool_cpu" {
  description = "CPU allocation for worker pool containers"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.083", "0.167", "0.25", "0.33", "0.5", "0.583", "0.667", "0.75", "0.833", "1", "1.33", "1.5", "2", "4", "6", "8"
    ], var.worker_pool_cpu)
    error_message = "CPU must be a valid Cloud Run CPU allocation."
  }
}

variable "worker_pool_min_instances" {
  description = "Minimum number of worker pool instances"
  type        = number
  default     = 1
  validation {
    condition     = var.worker_pool_min_instances >= 0 && var.worker_pool_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "worker_pool_max_instances" {
  description = "Maximum number of worker pool instances"
  type        = number
  default     = 10
  validation {
    condition     = var.worker_pool_max_instances >= 1 && var.worker_pool_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "worker_pool_concurrency" {
  description = "Maximum number of concurrent requests per worker pool instance"
  type        = number
  default     = 1000
  validation {
    condition     = var.worker_pool_concurrency >= 1 && var.worker_pool_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

# Monitoring Configuration Variables
variable "enable_monitoring_dashboard" {
  description = "Whether to create a Cloud Monitoring dashboard"
  type        = bool
  default     = true
}

variable "enable_alert_policies" {
  description = "Whether to create Cloud Monitoring alert policies"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

# Security Configuration Variables
variable "enable_vpc_connector" {
  description = "Whether to create and use a VPC connector for Cloud Run"
  type        = bool
  default     = false
}

variable "vpc_network_name" {
  description = "Name of the VPC network (if using VPC connector)"
  type        = string
  default     = "default"
}

variable "enable_binary_authorization" {
  description = "Whether to enable Binary Authorization for container security"
  type        = bool
  default     = false
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    application = "behavioral-analytics"
    managed-by  = "terraform"
  }
}