# Variables for GCP Real-time Video Collaboration with WebRTC and Cloud Run

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "webrtc-signaling"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.service_name))
    error_message = "Service name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 1000
    error_message = "Minimum instances must be between 0 and 1000."
  }
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 1000
    error_message = "Maximum instances must be between 1 and 1000."
  }
}

variable "memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.memory)
    error_message = "Memory must be a valid Cloud Run memory allocation."
  }
}

variable "cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "1", "2", "4", "6", "8"
    ], var.cpu)
    error_message = "CPU must be a valid Cloud Run CPU allocation."
  }
}

variable "container_port" {
  description = "Port that the container listens on"
  type        = number
  default     = 8080
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

variable "firestore_location" {
  description = "Location for Firestore database (multi-region or specific region)"
  type        = string
  default     = "nam5"  # North America multi-region
  validation {
    condition = contains([
      "nam5", "eur3", "asia-southeast1", "us-central1", "us-east1", "us-west1",
      "europe-west1", "europe-west3", "asia-east1", "asia-northeast1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "enable_iap" {
  description = "Enable Identity-Aware Proxy for the Cloud Run service"
  type        = bool
  default     = true
}

variable "iap_support_email" {
  description = "Support email for OAuth consent screen (required if enable_iap is true)"
  type        = string
  default     = ""
  validation {
    condition     = var.iap_support_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.iap_support_email))
    error_message = "IAP support email must be a valid email address or empty."
  }
}

variable "authorized_users" {
  description = "List of email addresses authorized to access the application via IAP"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.authorized_users : 
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All authorized users must have valid email addresses."
  }
}

variable "container_image" {
  description = "Container image for the WebRTC signaling server"
  type        = string
  default     = "gcr.io/cloudrun/hello"  # Default placeholder, will be replaced with actual build
}

variable "environment_variables" {
  description = "Environment variables for the Cloud Run service"
  type        = map(string)
  default     = {}
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    environment = "development"
    application = "webrtc-collaboration"
    managed-by  = "terraform"
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for Firestore database"
  type        = bool
  default     = false
}