# Input variables for browser-based AI applications infrastructure
# These variables configure the Cloud Shell Editor, Vertex AI, Cloud Build, and Cloud Run environment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Vertex AI."
  }
}

variable "service_name" {
  description = "Name of the Cloud Run service for the AI chat application"
  type        = string
  default     = "ai-chat-assistant"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.service_name))
    error_message = "Service name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "repository_name" {
  description = "Name of the Artifact Registry repository for container images"
  type        = string
  default     = "ai-app-repo"
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.repository_name))
    error_message = "Repository name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service (in vCPUs)"
  type        = string
  default     = "1"
  validation {
    condition = contains([
      "0.08", "0.17", "0.25", "0.33", "0.5", "0.58", "0.67", "0.75", "0.83", "1", "2", "4", "6", "8"
    ], var.cloud_run_cpu)
    error_message = "CPU must be a valid Cloud Run CPU allocation value."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "1Gi"
  validation {
    condition     = can(regex("^[1-9][0-9]*[GM]i$", var.cloud_run_memory))
    error_message = "Memory must be specified in Gi or Mi format (e.g., 1Gi, 512Mi)."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances for scaling"
  type        = number
  default     = 10
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances to keep warm"
  type        = number
  default     = 0
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= 100
    error_message = "Min instances must be between 0 and 100."
  }
}

variable "vertex_ai_location" {
  description = "Location for Vertex AI resources (must support Gemini models)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west4",
      "europe-west1", "europe-west4", "asia-northeast1"
    ], var.vertex_ai_location)
    error_message = "Vertex AI location must support Gemini models."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  validation {
    condition = contains([
      "dev", "staging", "prod", "demo", "test"
    ], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo, test."
  }
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "ai-development"
    application = "chat-assistant"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z]([a-z0-9_-]{0,62}[a-z0-9])?$", k))
    ])
    error_message = "Label keys must be lowercase and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "cloud_build_timeout" {
  description = "Timeout for Cloud Build operations (in seconds)"
  type        = number
  default     = 1200
  validation {
    condition     = var.cloud_build_timeout >= 120 && var.cloud_build_timeout <= 86400
    error_message = "Build timeout must be between 120 seconds (2 minutes) and 86400 seconds (24 hours)."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to the Cloud Run service"
  type        = bool
  default     = true
}

variable "artifact_registry_format" {
  description = "Format of the Artifact Registry repository"
  type        = string
  default     = "DOCKER"
  validation {
    condition = contains([
      "DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM", "GOOGET"
    ], var.artifact_registry_format)
    error_message = "Repository format must be a valid Artifact Registry format."
  }
}