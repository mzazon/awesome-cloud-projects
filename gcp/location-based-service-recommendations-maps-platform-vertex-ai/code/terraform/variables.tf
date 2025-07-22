# Input Variables
# This file defines all the input variables for the location-based recommendation system

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "location-recommender"
  
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.service_name))
    error_message = "Service name must be lowercase letters, numbers, and hyphens only."
  }
}

variable "database_name" {
  description = "Name for the Firestore database"
  type        = string
  default     = "recommendations-db"
  
  validation {
    condition     = length(var.database_name) >= 4 && length(var.database_name) <= 63
    error_message = "Database name must be between 4 and 63 characters."
  }
}

variable "container_port" {
  description = "Port that the Cloud Run container listens on"
  type        = number
  default     = 8080
  
  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances > 0 && var.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}

variable "memory_limit" {
  description = "Memory limit for Cloud Run service"
  type        = string
  default     = "512Mi"
  
  validation {
    condition = can(regex("^[0-9]+(Mi|Gi)$", var.memory_limit))
    error_message = "Memory limit must be in Mi or Gi format (e.g., 512Mi, 1Gi)."
  }
}

variable "cpu_limit" {
  description = "CPU limit for Cloud Run service"
  type        = string
  default     = "1"
  
  validation {
    condition = can(regex("^[0-9]+(\\.5)?$", var.cpu_limit))
    error_message = "CPU limit must be a number or decimal with .5 (e.g., 1, 2, 0.5, 1.5)."
  }
}

variable "enable_maps_grounding" {
  description = "Enable Vertex AI Maps Grounding feature (requires manual approval)"
  type        = bool
  default     = false
}

variable "ai_model_name" {
  description = "Vertex AI model to use for recommendations"
  type        = string
  default     = "gemini-2.5-flash"
  
  validation {
    condition = contains([
      "gemini-2.5-flash",
      "gemini-1.5-pro",
      "gemini-1.5-flash"
    ], var.ai_model_name)
    error_message = "AI model must be one of: gemini-2.5-flash, gemini-1.5-pro, gemini-1.5-flash."
  }
}

variable "api_key_restrictions" {
  description = "List of API restrictions for the Maps Platform API key"
  type        = list(string)
  default = [
    "maps-backend.googleapis.com",
    "places-backend.googleapis.com",
    "geocoding-backend.googleapis.com"
  ]
}

variable "enable_audit_logs" {
  description = "Enable audit logging for the project"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "demo"
    application = "location-recommendations"
    managed-by  = "terraform"
  }
  
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "firestore_location" {
  description = "Location for Firestore database (multi-region or region)"
  type        = string
  default     = "nam5"
  
  validation {
    condition = contains([
      "nam5", "eur3", "asia-northeast1", "us-central1", 
      "us-east1", "us-west1", "europe-west1", "asia-east1"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or regional location."
  }
}

variable "enable_vpc_connector" {
  description = "Enable VPC connector for Cloud Run (for private network access)"
  type        = bool
  default     = false
}

variable "vpc_connector_machine_type" {
  description = "Machine type for VPC connector instances"
  type        = string
  default     = "e2-micro"
  
  validation {
    condition = contains([
      "e2-micro", "e2-standard-4", "f1-micro"
    ], var.vpc_connector_machine_type)
    error_message = "VPC connector machine type must be e2-micro, e2-standard-4, or f1-micro."
  }
}